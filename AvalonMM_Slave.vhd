library ieee;
use ieee.std_logic_1164.all;
--use ieee.numeric_std.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

entity AvalonMM_Slave is
  port (
    -- Основные сигналы
    clk_80MHz : in std_logic; -- Тактовый сигнал 80МГц
    nRST : in std_logic; -- Асинхронный сброс (активный 0)
   
    -- Avalon-MM интерфейс от мастера
    address_master : in std_logic_vector(24 downto 0); -- Адресная шина (25 бит)
    read_master : in std_logic; -- Сигнал чтения
    write_master : in std_logic; -- Сигнал записи
    write_data_master : in std_logic_vector(63 downto 0); -- Шина данных записи (64 бита)
    byte_enable_master: in std_logic_vector(7 downto 0); -- Байтовая маска (8 бит)
    burstcount_master : in std_logic_vector(3 downto 0); -- Счетчик пакетной передачи
    burstenable_master : in std_logic;

    -- Avalon-MM интерфейс к мастеру
    read_data_avs : out std_logic_vector(63 downto 0); -- Шина данных чтения
    waitrequest_avs : out std_logic; -- Сигнал ожидания
   
    -- Интерфейсы к FIFO (логика управления FIFO)
    -- Командная FIFO записи
    wr_cmd_full : in std_logic; -- Флаг заполненности CMD_W_FIFO
    wr_cmd : out std_logic_vector(57 downto 0); -- Команда записи (58 бит)
    wr_cmd_write : out std_logic; -- Строб записи команд
   
    -- Данные FIFO записи
    wr_data_full : in std_logic; -- Флаг заполненности DATA_W_FIFO
    wr_data : out std_logic_vector(63 downto 0); -- Данные для записи
    wr_data_write : out std_logic; -- Строб записи данных
   
    -- Командная FIFO чтения
    rd_cmd_empty : in std_logic; -- Флаг пустоты CMD_R_FIFO
    rd_cmd : in std_logic_vector(33 downto 0); -- Команда чтения
    rd_cmd_read : out std_logic; -- Строб чтения команд
   
    -- Данные FIFO чтения
    rd_data_empty : in std_logic; -- Флаг пустоты DATA_R_FIFO
    rd_data : in std_logic_vector(63 downto 0); -- Прочитанные данные
    rd_data_read : out std_logic -- Строб чтения данных
  );
end entity AvalonMM_Slave;

architecture rtl of AvalonMM_Slave is
  
  -- FSM для работы с мастером
  type master_state_t is ( -- FSM для формирования запросов и для ответов мастеру
    IDLE,
    SINGLE_READ, --До этого захват
    PREPARE_HEADER, -- Пересчёт + формирование 
    WRITE_HEADER, -- Запись заголовка
    WAIT_READ_DATA, -- Ожидание ответа в read_cmd FIFO
    SEND_READ_DATA, -- Отправка данных на master
    SINGLE_WRITE,
    WRITE_DATA, -- Запись данных после формирования заголовка
    BURST_READ,
    BURST_WRITE
  );

  type internal_state_t is ( -- FSM для запросов отклика
    IDLE,
    READ_HEADER, -- Не пустое read_cmd FIFO
    PREPARE_ANSWER, -- Пересчёт для be
    READ_DATA -- Чтение данных
  );
    
  -- Сигналы FSM
  signal master_state   : master_state_t;
  signal internal_state : internal_state_t;
  
  -- Захваченные параметры транзакции
  signal captured_addr_avalon_r : std_logic_vector(24 downto 0);
  signal captured_be_avalon_r   : std_logic_vector(7 downto 0);
  
  -- Регистры
  signal op_id_r : std_logic_vector(7 downto 0);
 
  -- Регистры данных
  signal read_data_r : std_logic_vector(63 downto 0);
  signal waitrequest_r : std_logic;
 
  -- Значения
  signal data_width_r : std_logic_vector(11 downto 0);
 
  -- Внутренние сигналы для стробов
  signal wr_cmd_write_r  : std_logic;
  signal wr_data_write_r : std_logic;
  signal rd_cmd_read_r   : std_logic;
  signal rd_data_read_r  : std_logic;
 
  -- Итоговый сигнал команды
  signal exec_cmd_r : std_logic_vector(wr_cmd'length-1 downto 0);
  alias cmd_operation_type_ra : std_logic is exec_cmd_r(exec_cmd_r'length-1);
  alias cmd_address_ra : std_logic_vector(captured_addr_avalon_r'length-1 downto 0) is exec_cmd_r(56 downto 32);
  alias cmd_datawidth_ra : std_logic_vector(data_width_r'length-1 downto 0) is exec_cmd_r(31 downto 20);
  alias cmd_be_ra : std_logic_vector(captured_be_avalon_r'length-1 downto 0) is exec_cmd_r(19 downto 12); 
  alias cmd_operation_id_ra : std_logic_vector(op_id_r'length-1 downto 0) is exec_cmd_r(7 downto 0);

  signal response_cmd_r : std_logic_vector(rd_cmd'length-1 downto 0);

  function calc_be_params(be : std_logic_vector(7 downto 0))
    return std_logic_vector is
    variable ones_cnt  : integer := 0;
    variable first_one : integer := 0;
    variable found     : boolean := false;
    variable res       : std_logic_vector(11 downto 0);
  begin
    for i in 0 to 7 loop
      if be(i) = '1' then
        ones_cnt := ones_cnt + 1;
        if not found then
          first_one := i;
          found := true;
        end if;
      end if;
    end loop;

    res(11 downto 4) := conv_std_logic_vector(ones_cnt * 8, 8);
    res(3 downto 0)  := conv_std_logic_vector(first_one, 4);
    return res;
  end function;

begin

  waitrequest_avs <= waitrequest_r when (read_master = '1' or write_master = '1') else '0';
  wr_cmd_write    <= wr_cmd_write_r;
  wr_data_write   <= wr_data_write_r;
  rd_cmd_read     <= rd_cmd_read_r;
  rd_data_read    <= rd_data_read_r;
  wr_cmd          <= exec_cmd_r;


  master_fsm: process(clk_80MHz, nRST)
  begin
    if nRST = '0' then
      master_state <= IDLE;
    elsif rising_edge(clk_80MHz) then

      case master_state is

        when IDLE =>
          if read_master = '1' and burstenable_master = '0' then
            master_state <= SINGLE_READ;
          elsif write_master = '1' and burstenable_master = '0' then
            master_state <= SINGLE_WRITE;
          end if;

        when SINGLE_READ =>
          master_state <= PREPARE_HEADER;

        when SINGLE_WRITE =>
          master_state <= PREPARE_HEADER;

        when PREPARE_HEADER =>
		    if wr_cmd_full = '0' then
				master_state <= WRITE_HEADER;
			 end if;

        when WRITE_HEADER =>
		    if write_master = '1' then
            master_state <= IDLE;
          else
            master_state <= WAIT_READ_DATA;
          end if;

        when WAIT_READ_DATA =>
          if internal_state = READ_DATA then
            master_state <= SEND_READ_DATA;
          end if;

        when SEND_READ_DATA =>
          master_state <= IDLE;

        when others =>
          master_state <= IDLE;

      end case;

    end if;
  end process;

  internal_fsm: process(clk_80MHz, nRST)
  begin
    if nRST = '0' then
      internal_state <= IDLE;
    elsif rising_edge(clk_80MHz) then

      case internal_state is

        when IDLE =>
          if rd_cmd_empty = '0' then
            internal_state <= READ_HEADER;
          end if;

        when READ_HEADER =>
          internal_state <= PREPARE_ANSWER;

        when READ_DATA =>
          if rd_data_empty = '0' then
            internal_state <= IDLE;
          end if;

        when PREPARE_ANSWER =>
          internal_state <= READ_DATA;

        when others =>
          internal_state <= IDLE;

      end case;

    end if;
  end process;

signals: process(clk_80MHz, nRST)
begin
  if nRST = '0' then
    waitrequest_r <= '1';
    read_data_avs <= (others => '0');

    wr_cmd_write_r  <= '0';
    wr_data_write_r <= '0';
    rd_cmd_read_r   <= '0';
    rd_data_read_r  <= '0';

    captured_addr_avalon_r <= (others => '0');
    captured_be_avalon_r   <= (others => '0');
    data_width_r           <= (others => '0');
    read_data_r            <= (others => '0');
    exec_cmd_r             <= (others => '0');
    response_cmd_r         <= (others => '0');
    op_id_r                <= (others => '0');

  elsif rising_edge(clk_80MHz) then

    waitrequest_r      <= waitrequest_r;
    --read_data_avs      <= read_data_avs;

    captured_addr_avalon_r <= captured_addr_avalon_r;
    captured_be_avalon_r   <= captured_be_avalon_r;
    data_width_r           <= data_width_r;
    read_data_r            <= read_data_r;
    exec_cmd_r             <= exec_cmd_r;
    response_cmd_r         <= response_cmd_r;
    op_id_r                <= op_id_r;

    if master_state = IDLE and (read_master = '1' or write_master = '1') then
      captured_addr_avalon_r <= address_master;
    end if;

    if master_state = IDLE and (read_master = '1' or write_master = '1') then
      captured_be_avalon_r <= byte_enable_master;
    end if;

    if master_state = PREPARE_HEADER then
      data_width_r <= calc_be_params(captured_be_avalon_r);
    end if;

    if master_state = PREPARE_HEADER then
      cmd_operation_type_ra <= write_master;
    end if;

    if master_state = PREPARE_HEADER then
      cmd_address_ra <= captured_addr_avalon_r;
    end if;

    if master_state = PREPARE_HEADER then
      cmd_datawidth_ra <= data_width_r;
    end if;

    if master_state = PREPARE_HEADER then
      cmd_be_ra <= captured_be_avalon_r;
    end if;

    if master_state = PREPARE_HEADER then
      cmd_operation_id_ra <= op_id_r;
    end if;

    if master_state = WRITE_HEADER and wr_cmd_full = '0' then
      wr_cmd_write_r <= '1';
    else
      wr_cmd_write_r <= '0';
    end if;

    if master_state = WRITE_HEADER and wr_cmd_full = '0' and write_master = '1' then
      wr_data <= write_data_master;
    end if;

    if master_state = WRITE_HEADER and wr_cmd_full = '0' and write_master = '1' then
      wr_data_write_r <= '1';
    else
      wr_data_write_r <= '0';
    end if;

    if internal_state = READ_HEADER then
      rd_cmd_read_r <= '1';
    else
      rd_cmd_read_r <= '0';
    end if;

    if internal_state = READ_HEADER then
      response_cmd_r <= rd_cmd;
    end if;

    if internal_state = READ_DATA and rd_data_empty = '0' then
      rd_data_read_r <= '1';
    else
      rd_data_read_r <= '0';
    end if;

    if internal_state = READ_DATA and rd_data_empty = '0' then
      read_data_r <= rd_data;
    end if;

    if master_state = SEND_READ_DATA then
      read_data_avs <= read_data_r;
    end if;

    if master_state = SEND_READ_DATA then
      waitrequest_r <= '0';
    end if;
  end if;
end process signals;
end architecture rtl;
