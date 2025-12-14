library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity AvalonMM_Slave is
  port (
    -- Основные сигналы (из таблицы Avalon slave)
    clk_80MHz         : in  std_logic;                    -- Тактовый сигнал 80МГц
    nRST              : in  std_logic;                    -- Асинхронный сброс (активный 0)
    
    -- Avalon-MM интерфейс от мастера
    address_master    : in  std_logic_vector(24 downto 0);  -- Адресная шина (25 бит)
    read_master       : in  std_logic;                               -- Сигнал чтения
    write_master      : in  std_logic;                               -- Сигнал записи
    write_data_master : in  std_logic_vector(63 downto 0); -- Шина данных записи (64 бита)
    byte_enable_master: in std_logic_vector(3 downto 0); -- Байтовая маска (4 бита)
    burstcount_master : in  std_logic_vector(3 downto 0);            -- Счетчик пакетной передачи
    
    -- Avalon-MM интерфейс к мастеру
    read_data_avs     : out std_logic_vector(63 downto 0); -- Шина данных чтения
    waitrequest_avs   : out std_logic;                               -- Сигнал ожидания
    
    -- Интерфейсы к FIFO (логика управления ↔ FIFO)
    -- Командная FIFO записи
    wr_cmd_full       : in  std_logic;     -- Флаг заполненности CMD_W_FIFO
    wr_cmd            : out std_logic_vector(53 downto 0);   -- Команда записи (54 бита)
    wr_cmd_write      : buffer std_logic;  -- Строб записи команд (buffer чтобы читать внутри)
    
    -- Данные FIFO записи
    wr_data_full      : in  std_logic;     -- Флаг заполненности DATA_W_FIFO
    wr_data           : out std_logic_vector(63 downto 0);  -- Данные для записи
    wr_data_write     : out std_logic;     -- Строб записи данных
    
    -- Командная FIFO чтения
    rd_cmd_empty      : in  std_logic;     -- Флаг пустоты CMD_R_FIFO
    rd_cmd            : in  std_logic_vector(23 downto 0);  -- Команда чтения (24 бита: 8 + 16)
    rd_cmd_read       : out std_logic;     -- Строб чтения команд
    
    -- Данные FIFO чтения
    rd_data_empty     : in  std_logic;     -- Флаг пустоты DATA_R_FIFO
    rd_data           : in  std_logic_vector(63 downto 0);  -- Прочитанные данные
    rd_data_read      : out std_logic      -- Строб чтения данных
  );
end entity AvalonMM_Slave;

architecture rtl of AvalonMM_Slave is

  constant ADDR_WIDTH     : integer := 25;
  constant DATA_WIDTH     : integer := 64;
  constant BYTEEN_WIDTH   : integer := 4;  -- DATA_WIDTH / 8
  constant CMD_WIDTH      : integer := 54; -- 1 + ADDR_WIDTH + 16 + BYTEEN_WIDTH + 8
  constant RESP_WIDTH     : integer := 24; -- 8 + 16

  -- FSM для работы с мастером
  type master_state_t is (IDLE, READ_BURST, WRITE_BURST);
  type internal_state_t is (INT_IDLE, WR_CMD_SENT, RD_CMD_SENT);

  -- Функции
  function count_ones(be : std_logic_vector) return std_logic_vector is
    variable cnt : integer := 0;
  begin
    for i in be'range loop
      if be(i) = '1' then cnt := cnt + 1; end if;
    end loop;
    return std_logic_vector(to_unsigned(cnt, 8));
  end function;

  function lowest_enabled_byte(be : std_logic_vector) return std_logic_vector is
  begin
    for i in be'low to be'high loop
      if be(i) = '1' then return std_logic_vector(to_unsigned(i, 8)); end if;
    end loop;
    return std_logic_vector(to_unsigned(0, 8));
  end function;

  function state_to_sl(state : master_state_t) return std_logic is
  begin
    case state is
      when WRITE_BURST => return '1';
      when others => return '0';
    end case;
  end function;

  -- Сигналы FSM
  signal master_state_r     : master_state_t := IDLE;
  signal internal_state_r   : internal_state_t := INT_IDLE;

  -- Захваченные параметры транзакции
  signal captured_addr_r    : std_logic_vector(ADDR_WIDTH-1 downto 0);
  signal captured_be_r      : std_logic_vector(BYTEEN_WIDTH-1 downto 0);
  signal captured_burst_r   : std_logic_vector(3 downto 0);
  signal captured_byte_offset_r : std_logic_vector(7 downto 0);
  signal captured_active_bytes_r : std_logic_vector(7 downto 0);

  -- Регистры
  signal op_id_r            : std_logic_vector(7 downto 0) := (others => '0');
  signal master_beats_remaining_r : std_logic_vector(7 downto 0);
  
  -- Счетчики для отслеживания прогресса
  signal write_beats_sent_r     : std_logic_vector(7 downto 0);
  signal read_beats_received_r  : std_logic_vector(7 downto 0);
  
  signal read_data_r        : std_logic_vector(DATA_WIDTH-1 downto 0);
  signal waitrequest_r      : std_logic;
  
  -- Флаги для отслеживания отправки команд
  signal wr_cmd_sent_r      : std_logic;
  signal rd_cmd_sent_r      : std_logic;
  
  -- Внутренние сигналы для стробов
  signal wr_cmd_write_int   : std_logic;
  signal wr_data_write_int  : std_logic;
  signal rd_cmd_read_int    : std_logic;
  signal rd_data_read_int   : std_logic;
  
begin

  read_data_avs   <= read_data_r;
  waitrequest_avs <= waitrequest_r;
  
  -- Связь внутренних сигналов с выходами
  wr_cmd_write <= wr_cmd_write_int;
  wr_data_write <= wr_data_write_int;
  rd_cmd_read <= rd_cmd_read_int;
  rd_data_read <= rd_data_read_int;

  -- FSM для работы с Avalon-MM мастером
  master_state_process: process(clk_80MHz, nRST)
  begin
    if nRST = '0' then
      master_state_r <= IDLE;
    elsif rising_edge(clk_80MHz) then
      case master_state_r is
        when IDLE =>
          if write_master = '1' and waitrequest_r = '0' and wr_data_full = '0' then
            master_state_r <= WRITE_BURST;
          elsif read_master = '1' and waitrequest_r = '0' and wr_cmd_full = '0' then
            master_state_r <= READ_BURST;
          end if;

        when WRITE_BURST =>
          if master_beats_remaining_r = std_logic_vector(to_unsigned(1, 8)) or 
             (write_master = '0' and waitrequest_r = '0') then
            master_state_r <= IDLE;
          end if;

        when READ_BURST =>
          if master_beats_remaining_r = std_logic_vector(to_unsigned(1, 8)) or 
             (read_master = '0' and waitrequest_r = '0') then
            master_state_r <= IDLE;
          end if;
      end case;
    end if;
  end process;

  -- FSM для работы с внутренней логикой (Логика управления)
  internal_state_process: process(clk_80MHz, nRST)
  begin
    if nRST = '0' then
      internal_state_r <= INT_IDLE;
    elsif rising_edge(clk_80MHz) then
      case internal_state_r is
        when INT_IDLE =>
          if master_state_r = WRITE_BURST and wr_cmd_full = '0' and wr_cmd_sent_r = '0' then
            -- Переходим в состояние ожидания отправки команды записи
            internal_state_r <= WR_CMD_SENT;
          elsif master_state_r = READ_BURST and wr_cmd_full = '0' and rd_cmd_sent_r = '0' then
            -- Переходим в состояние ожидания отправки команды чтения
            internal_state_r <= RD_CMD_SENT;
          end if;

        when WR_CMD_SENT =>
          -- Команда записи отправлена, возвращаемся в IDLE
          if wr_cmd_write_int = '1' then
            internal_state_r <= INT_IDLE;
          end if;

        when RD_CMD_SENT =>
          -- Команда чтения отправлена, возвращаемся в IDLE
          if wr_cmd_write_int = '1' then
            internal_state_r <= INT_IDLE;
          end if;
      end case;
    end if;
  end process;

  -- Процесс для основной логики данных (Логика управления)
  data_process: process(clk_80MHz, nRST)
    variable data_to_write : std_logic_vector(DATA_WIDTH-1 downto 0);
    variable expected_bytes : std_logic_vector(15 downto 0);
  begin
    if nRST = '0' then
      -- сброс всех сигналов
      master_beats_remaining_r <= (others => '0');
      write_beats_sent_r       <= (others => '0');
      read_beats_received_r    <= (others => '0');
      read_data_r              <= (others => '0');
      
      captured_addr_r          <= (others => '0');
      captured_be_r            <= (others => '0');
      captured_burst_r         <= (others => '0');
      captured_byte_offset_r   <= (others => '0');
      captured_active_bytes_r  <= (others => '0');

      wr_data_write_int <= '0';
      rd_data_read_int  <= '0';
      wr_cmd_write_int  <= '0';
      rd_cmd_read_int   <= '0';

      op_id_r <= (others => '0');
      waitrequest_r <= '1';
      
      wr_cmd_sent_r <= '0';
      rd_cmd_sent_r <= '0';

    elsif rising_edge(clk_80MHz) then
      -- сброс всех стробов
      wr_data_write_int <= '0';
      rd_data_read_int  <= '0';
      wr_cmd_write_int  <= '0';
      rd_cmd_read_int   <= '0';
      
      -- Сброс флагов отправки команд, когда возвращаемся в IDLE
      if internal_state_r = INT_IDLE then
        wr_cmd_sent_r <= '0';
        rd_cmd_sent_r <= '0';
      end if;

      -- Логика waitrequest_r
      case master_state_r is
        when IDLE =>
          if (write_master = '1' and wr_data_full = '0') or 
             (read_master = '1' and wr_cmd_full = '0') then
            waitrequest_r <= '0';
          else
            waitrequest_r <= '1';
          end if;
          
        when WRITE_BURST =>
          if wr_data_full = '0' and master_beats_remaining_r /= std_logic_vector(to_unsigned(0, 8)) then
            waitrequest_r <= '0';
          else
            waitrequest_r <= '1';
          end if;
          
        when READ_BURST =>
          if rd_data_empty = '0' and master_beats_remaining_r /= std_logic_vector(to_unsigned(0, 8)) then
            waitrequest_r <= '0';
          else
            waitrequest_r <= '1';
          end if;
          
        when others =>
          waitrequest_r <= '1';
      end case;

      -- Захват параметров транзакции при начале
      if master_state_r = IDLE and internal_state_r = INT_IDLE and waitrequest_r = '0' then
        captured_addr_r <= address_master;
        captured_be_r <= byte_enable_master;
        captured_burst_r <= burstcount_master;
        captured_byte_offset_r <= lowest_enabled_byte(byte_enable_master);
        captured_active_bytes_r <= count_ones(byte_enable_master);
        
        if write_master = '1' then
          master_beats_remaining_r <= "0000" & burstcount_master;
          write_beats_sent_r <= (others => '0');
        else -- read_master = '1'
          master_beats_remaining_r <= "0000" & burstcount_master;
          read_beats_received_r <= (others => '0');
        end if;
      end if;

      -- Логика записи данных
      if master_state_r = WRITE_BURST then
        if write_master = '1' and waitrequest_r = '0' then
          data_to_write := std_logic_vector(shift_right(unsigned(write_data_master), 
            to_integer(unsigned(captured_byte_offset_r)) * 8));
          
          wr_data <= data_to_write;
          wr_data_write_int <= '1';
          write_beats_sent_r <= std_logic_vector(unsigned(write_beats_sent_r) + 1);
          
          if master_beats_remaining_r /= std_logic_vector(to_unsigned(0, 8)) then
            master_beats_remaining_r <= std_logic_vector(unsigned(master_beats_remaining_r) - 1);
          end if;
        end if;
      end if;

      -- Логика чтения данных
      if master_state_r = READ_BURST then
        if read_master = '1' and waitrequest_r = '0' then
          read_data_r <= std_logic_vector(shift_left(unsigned(rd_data), 
            to_integer(unsigned(captured_byte_offset_r)) * 8));
          rd_data_read_int <= '1';
          
          read_beats_received_r <= std_logic_vector(unsigned(read_beats_received_r) + 1);
          
          if master_beats_remaining_r /= std_logic_vector(to_unsigned(0, 8)) then
            master_beats_remaining_r <= std_logic_vector(unsigned(master_beats_remaining_r) - 1);
          end if;
        end if;
      end if;

      -- Логика отправки команд к бэкенду
      case internal_state_r is
        when WR_CMD_SENT =>
          -- Отправка команды записи (после первого слова данных)
          if wr_cmd_full = '0' then
            expected_bytes := std_logic_vector(to_unsigned(
              to_integer(unsigned(captured_active_bytes_r)) * to_integer(unsigned(captured_burst_r)), 16));
            
            wr_cmd <= state_to_sl(master_state_r) &
                       std_logic_vector(unsigned(captured_addr_r) + unsigned(captured_byte_offset_r)) &
                       expected_bytes &
                       captured_be_r &
                       op_id_r;
            wr_cmd_write_int <= '1';
            op_id_r <= std_logic_vector(unsigned(op_id_r) + 1);
            wr_cmd_sent_r <= '1';
          end if;
          
        when RD_CMD_SENT =>
          -- Отправка команды чтения
          if wr_cmd_full = '0' then
            expected_bytes := std_logic_vector(to_unsigned(
              to_integer(unsigned(captured_active_bytes_r)) * to_integer(unsigned(captured_burst_r)), 16));
            
            wr_cmd <= state_to_sl(master_state_r) &
                       std_logic_vector(unsigned(captured_addr_r) + unsigned(captured_byte_offset_r)) &
                       expected_bytes &
                       captured_be_r &
                       op_id_r;
            wr_cmd_write_int <= '1';
            op_id_r <= std_logic_vector(unsigned(op_id_r) + 1);
            rd_cmd_sent_r <= '1';
          end if;
          
        when others =>
          null;
      end case;

      if rd_cmd_empty = '0' then
        rd_cmd_read_int <= '1';
        if rd_cmd(23 downto 16) /= x"00" then
          null;
        end if;
      end if;
      
    end if;
  end process;

end architecture rtl;
