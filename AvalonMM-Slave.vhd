library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity AvalonMM_Slave is
  generic (
    ADDR_WIDTH       : integer := 25;
    DATA_WIDTH       : integer := 32
  );
  port (
    clk         : in  std_logic;
    reset_n     : in  std_logic;

    address     : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
    read        : in  std_logic;
    write       : in  std_logic;
    writedata   : in  std_logic_vector(DATA_WIDTH-1 downto 0);
    byteenable  : in  std_logic_vector((DATA_WIDTH/8)-1 downto 0);
    burstcount  : in  std_logic_vector(3 downto 0);

    readdata    : out std_logic_vector(DATA_WIDTH-1 downto 0);
    waitrequest : out std_logic;
    
    avalonmm_host_wait : in std_logic := '0'
  );
end entity AvalonMM_Slave;

architecture rtl of AvalonMM_Slave is

  constant BYTEEN_WIDTH : integer := DATA_WIDTH / 8;
  constant CMD_WIDTH    : integer := 1 + ADDR_WIDTH + 16 + BYTEEN_WIDTH + 8;
  constant RESP_WIDTH   : integer := 8 + 16;

  -- FSM для работы с мастером
  type master_state_t is (IDLE, READ_BURST, WRITE_BURST);
  type internal_state_t is (INT_IDLE, WR_CMD_SENT, RD_CMD_SENT, RD_WAIT_DATA);

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

  -- FIFO к бэкенду
  signal wr_cmd        : std_logic_vector(CMD_WIDTH-1 downto 0);
  signal wr_cmd_write     : std_logic;
  signal wr_cmd_full      : std_logic := '0';

  signal wr_data       : std_logic_vector(DATA_WIDTH-1 downto 0);
  signal wr_data_write : std_logic;
  signal wr_data_full  : std_logic := '0';

  signal rd_cmd        : std_logic_vector(RESP_WIDTH-1 downto 0) := (others => '0');
  signal rd_cmd_read   : std_logic;
  signal rd_cmd_empty  : std_logic := '1';

  signal rd_data       : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');
  signal rd_data_read  : std_logic;
  signal rd_data_empty : std_logic := '1';

  -- Сигналы FSM
  signal master_state_r     : master_state_t := IDLE;
  signal internal_state_r   : internal_state_t := INT_IDLE;

  -- Захваченные параметры транзакции
  signal captured_addr_r    : std_logic_vector(ADDR_WIDTH-1 downto 0) := (others => '0');
  signal captured_be_r      : std_logic_vector(BYTEEN_WIDTH-1 downto 0) := (others => '0');
  signal captured_burst_r   : std_logic_vector(3 downto 0) := (others => '0');
  signal captured_byte_offset_r : std_logic_vector(7 downto 0) := (others => '0');
  signal captured_active_bytes_r : std_logic_vector(7 downto 0) := (others => '0');

  -- Регистры
  signal op_id_r            : std_logic_vector(7 downto 0) := (others => '0');
  signal master_beats_remaining_r : std_logic_vector(7 downto 0) := (others => '0');
  signal internal_beats_remaining_r : std_logic_vector(7 downto 0) := (others => '0');
  signal remaining_bytes_r  : std_logic_vector(15 downto 0) := (others => '0');
  
  -- Счетчики для отслеживания прогресса
  signal write_beats_sent_r     : std_logic_vector(7 downto 0) := (others => '0');
  signal read_beats_received_r  : std_logic_vector(7 downto 0) := (others => '0');
  
  signal readdata_r         : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');
  signal waitrequest_r      : std_logic := '1';
  
  -- НОВЫЕ РЕГИСТРЫ: для удержания данных при ожидании
  signal write_data_hold_r  : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');
  signal write_hold_valid_r : std_logic := '0';
  signal read_data_hold_r   : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');
  signal read_hold_valid_r  : std_logic := '0';
  
  -- Сигналы для управления командами записи
  signal first_write_data_sent_r : std_logic := '0';

begin

  readdata    <= readdata_r;
  waitrequest <= waitrequest_r;

  -- FSM для работы с Avalon-MM мастером
  master_state_process: process(clk, reset_n)
  begin
    if reset_n = '0' then
      master_state_r <= IDLE;
    elsif rising_edge(clk) then
      case master_state_r is
        when IDLE =>
          if write = '1' and internal_state_r = INT_IDLE and avalonmm_host_wait = '0' then
            master_state_r <= WRITE_BURST;
          elsif read = '1' and internal_state_r = INT_IDLE and avalonmm_host_wait = '0' then
            master_state_r <= READ_BURST;
          end if;

        when WRITE_BURST =>
          if master_beats_remaining_r = std_logic_vector(to_unsigned(1, 8)) then
            master_state_r <= IDLE;
          elsif write = '0' then
            master_state_r <= IDLE;
          end if;

        when READ_BURST =>
          if master_beats_remaining_r = std_logic_vector(to_unsigned(1, 8)) then
            master_state_r <= IDLE;
          elsif read = '0' then
            master_state_r <= IDLE;
          end if;
      end case;
    end if;
  end process;

  -- FSM для работы с внутренней логикой
  internal_state_process: process(clk, reset_n)
  begin
    if reset_n = '0' then
      internal_state_r <= INT_IDLE;
      first_write_data_sent_r <= '0';
    elsif rising_edge(clk) then
      case internal_state_r is
        when INT_IDLE =>
          first_write_data_sent_r <= '0';
          if master_state_r = WRITE_BURST and wr_cmd_full = '0' and avalonmm_host_wait = '0' then
            internal_state_r <= WR_CMD_SENT;
          elsif master_state_r = READ_BURST and wr_cmd_full = '0' and avalonmm_host_wait = '0' then
            internal_state_r <= RD_CMD_SENT;
          end if;

        when WR_CMD_SENT =>
          if wr_data_write = '1' then
            first_write_data_sent_r <= '1';
          end if;
          
          if master_state_r /= WRITE_BURST then
            internal_state_r <= INT_IDLE;
          elsif unsigned(write_beats_sent_r) >= unsigned(captured_burst_r) then
            internal_state_r <= INT_IDLE;
          end if;

        when RD_CMD_SENT =>
          if rd_cmd_empty = '0' and avalonmm_host_wait = '0' then
            if remaining_bytes_r = std_logic_vector(to_unsigned(0, 16)) then
              internal_state_r <= INT_IDLE;
            else
              internal_state_r <= RD_WAIT_DATA;
            end if;
          end if;

          if master_state_r /= READ_BURST then
            internal_state_r <= INT_IDLE;
          end if;

        when RD_WAIT_DATA =>
          if master_state_r /= READ_BURST then
            internal_state_r <= INT_IDLE;
          elsif unsigned(read_beats_received_r) >= unsigned(captured_burst_r) then
            internal_state_r <= INT_IDLE;
          end if;
      end case;
    end if;
  end process;

  -- Процесс для удержания данных записи при ожидании
  write_data_hold_process: process(clk, reset_n)
  begin
    if reset_n = '0' then
      write_data_hold_r <= (others => '0');
      write_hold_valid_r <= '0';
    elsif rising_edge(clk) then
      if master_state_r = WRITE_BURST and write = '1' and waitrequest_r = '0' then
        if avalonmm_host_wait = '1' then
          write_data_hold_r <= std_logic_vector(shift_right(unsigned(writedata), 
            to_integer(unsigned(captured_byte_offset_r)) * 8));
          write_hold_valid_r <= '1';
        else
          write_hold_valid_r <= '0';
        end if;
      else
        write_hold_valid_r <= '0';
      end if;
    end if;
  end process;

  -- процесс для основной логики данных
  data_process: process(clk, reset_n)
    variable data_to_write : std_logic_vector(DATA_WIDTH-1 downto 0);
  begin
    if reset_n = '0' then
      -- сброс всех сигналов
      master_beats_remaining_r <= (others => '0');
      write_beats_sent_r       <= (others => '0');
      read_beats_received_r    <= (others => '0');
      readdata_r               <= (others => '0');
      read_data_hold_r         <= (others => '0');
      read_hold_valid_r        <= '0';
      
      captured_addr_r          <= (others => '0');
      captured_be_r            <= (others => '0');
      captured_burst_r         <= (others => '0');
      captured_byte_offset_r   <= (others => '0');
      captured_active_bytes_r  <= (others => '0');

      wr_data_write <= '0';
      rd_data_read  <= '0';
      wr_cmd_write  <= '0';
      rd_cmd_read   <= '0';

      op_id_r <= (others => '0');
      remaining_bytes_r <= (others => '0');
      internal_beats_remaining_r <= (others => '0');

    elsif rising_edge(clk) then
      -- сброс всех сигналов
      wr_data_write <= '0';
      rd_data_read  <= '0';
      wr_cmd_write  <= '0';
      rd_cmd_read   <= '0';

      -- Логика waitrequest_r с учетом avalonmm_host_wait
      if master_state_r = IDLE and internal_state_r = INT_IDLE then
        if ((write = '1' and wr_data_full = '0' and avalonmm_host_wait = '0') or 
            (read = '1' and wr_cmd_full = '0' and avalonmm_host_wait = '0')) then
          waitrequest_r <= '0';
        else
          waitrequest_r <= '1';
        end if;
      elsif master_state_r = WRITE_BURST then
        if wr_data_full = '0' and master_beats_remaining_r /= std_logic_vector(to_unsigned(0, 8)) 
           and avalonmm_host_wait = '0' then
          waitrequest_r <= '0';
        else
          waitrequest_r <= '1';
        end if;
      elsif master_state_r = READ_BURST then
        if rd_data_empty = '0' and master_beats_remaining_r /= std_logic_vector(to_unsigned(0, 8)) 
           and avalonmm_host_wait = '0' then
          waitrequest_r <= '0';
        else
          waitrequest_r <= '1';
        end if;
      else
        waitrequest_r <= '1';
      end if;

      -- Захват параметров транзакции
      if master_state_r = IDLE and internal_state_r = INT_IDLE and avalonmm_host_wait = '0' then
        if write = '1' or read = '1' then
          captured_addr_r <= address;
          captured_be_r <= byteenable;
          captured_burst_r <= burstcount;
          captured_byte_offset_r <= lowest_enabled_byte(byteenable);
          captured_active_bytes_r <= count_ones(byteenable);
          
          if write = '1' then
            master_beats_remaining_r <= "0000" & burstcount;
            write_beats_sent_r <= (others => '0');
          else -- read = '1'
            master_beats_remaining_r <= "0000" & burstcount;
            read_beats_received_r <= (others => '0');
          end if;
        end if;
      end if;

      -- Логика записи с удержанием данных при ожидании
      if master_state_r = WRITE_BURST then
        if write = '1' and waitrequest_r = '0' and avalonmm_host_wait = '0' then
          if write_hold_valid_r = '1' then
            data_to_write := write_data_hold_r;
          else
            data_to_write := std_logic_vector(shift_right(unsigned(writedata), 
              to_integer(unsigned(captured_byte_offset_r)) * 8));
          end if;
          
          wr_data <= data_to_write;
          wr_data_write <= '1';
          write_beats_sent_r <= std_logic_vector(unsigned(write_beats_sent_r) + 1);
          
          if master_beats_remaining_r /= std_logic_vector(to_unsigned(0, 8)) then
            master_beats_remaining_r <= std_logic_vector(unsigned(master_beats_remaining_r) - 1);
          end if;
        end if;
      end if;

      -- Логика чтения с удержанием данных при ожидании
      if master_state_r = READ_BURST then
        if read = '1' and waitrequest_r = '0' and avalonmm_host_wait = '0' then
          if read_hold_valid_r = '1' then
            readdata_r <= std_logic_vector(shift_left(unsigned(read_data_hold_r), 
              to_integer(unsigned(captured_byte_offset_r)) * 8));
            read_hold_valid_r <= '0';
          else
            readdata_r <= std_logic_vector(shift_left(unsigned(rd_data), 
              to_integer(unsigned(captured_byte_offset_r)) * 8));
            rd_data_read <= '1';
          end if;
          
          read_beats_received_r <= std_logic_vector(unsigned(read_beats_received_r) + 1);
          
          if master_beats_remaining_r /= std_logic_vector(to_unsigned(0, 8)) then
            master_beats_remaining_r <= std_logic_vector(unsigned(master_beats_remaining_r) - 1);
          end if;
        elsif read = '1' and waitrequest_r = '0' and avalonmm_host_wait = '1' then
          read_data_hold_r <= rd_data;
          read_hold_valid_r <= '1';
        end if;
      end if;

      -- Логика команд к бэкенду
      if internal_state_r = INT_IDLE and avalonmm_host_wait = '0' then
        if master_state_r = READ_BURST and wr_cmd_full = '0' then
          -- Для чтения: сразу отправляем команду
          wr_cmd <= state_to_sl(master_state_r) &
                     std_logic_vector(unsigned(captured_addr_r) + unsigned(captured_byte_offset_r)) &
                     std_logic_vector(to_unsigned(
                       to_integer(unsigned(captured_active_bytes_r)) * to_integer(unsigned(captured_burst_r)), 16)) &
                     captured_be_r &
                     op_id_r;
          wr_cmd_write <= '1';
          op_id_r <= std_logic_vector(unsigned(op_id_r) + 1);
          
        elsif master_state_r = WRITE_BURST and wr_cmd_full = '0' and first_write_data_sent_r = '1' then
          wr_cmd <= state_to_sl(master_state_r) &
                     std_logic_vector(unsigned(captured_addr_r) + unsigned(captured_byte_offset_r)) &
                     std_logic_vector(to_unsigned(
                       to_integer(unsigned(captured_active_bytes_r)) * to_integer(unsigned(captured_burst_r)), 16)) &
                     captured_be_r &
                     op_id_r;
          wr_cmd_write <= '1';
          op_id_r <= std_logic_vector(unsigned(op_id_r) + 1);
        end if;
      end if;

      -- Логика ответов от бэкенда
      if internal_state_r = RD_CMD_SENT and avalonmm_host_wait = '0' then
        if rd_cmd_empty = '0' then
          rd_cmd_read <= '1';
          remaining_bytes_r <= rd_cmd(15 downto 0);
          
          if to_integer(unsigned(captured_active_bytes_r)) > 0 then
            internal_beats_remaining_r <= std_logic_vector(
              (unsigned(rd_cmd(15 downto 0)) + unsigned(captured_active_bytes_r) - 1) / unsigned(captured_active_bytes_r)
            );
          else
            internal_beats_remaining_r <= (others => '0');
          end if;
        end if;
      end if;
    end if;
  end process;

end architecture rtl;
