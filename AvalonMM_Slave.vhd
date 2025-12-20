library ieee;
use ieee.std_logic_1164.all;
--use ieee.numeric_std.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

entity AvalonMM_Slave is
  port (
    -- Основные сигналы
    clk_80MHz : in std_logic;
    nRST : in std_logic;
   
    -- Avalon-MM интерфейс от мастера
    address_master : in std_logic_vector(24 downto 0);
    read_master : in std_logic;
    write_master : in std_logic;
    write_data_master : in std_logic_vector(63 downto 0);
    byte_enable_master: in std_logic_vector(7 downto 0);
    burstcount_master : in std_logic_vector(3 downto 0);
    burstenable_master : in std_logic;

    -- Avalon-MM интерфейс к мастеру
    read_data_avs : out std_logic_vector(63 downto 0);
    waitrequest_avs : out std_logic;
   
    -- Интерфейсы к FIFO (логика управления FIFO)
    -- Командная FIFO записи
    wr_cmd_full : in std_logic;
    wr_cmd : out std_logic_vector(65 downto 0);
    wr_cmd_write : out std_logic;
   
    -- Данные FIFO записи
    wr_data_full : in std_logic;
    wr_data : out std_logic_vector(63 downto 0);
    wr_data_write : out std_logic;
   
    -- Командная FIFO чтения
    rd_cmd_empty : in std_logic;
    rd_cmd : in std_logic_vector(33 downto 0);
    rd_cmd_read : out std_logic;
   
    -- Данные FIFO чтения
    rd_data_empty : in std_logic;
    rd_data : in std_logic_vector(63 downto 0);
    rd_data_read : out std_logic
  );
end entity AvalonMM_Slave;

architecture rtl of AvalonMM_Slave is
  
  -- FSM для работы с мастером
  type master_state_t is (
    IDLE,
    SINGLE_READ,
    PREPARE_HEADER,
    WRITE_HEADER,
    WAIT_READ_DATA,
    SEND_READ_DATA,
    SINGLE_WRITE,
    WRITE_DATA,
    BURST_READ,
    BURST_READ_DATA,
    BURST_WRITE,
    BURST_WRITE_DATA
  );

  type internal_state_t is (
    IDLE,
    READ_HEADER,
    PREPARE_ANSWER,
    READ_DATA
  );
    
  signal master_state   : master_state_t;
  signal internal_state : internal_state_t;
  
  signal captured_addr_avalon_r : std_logic_vector(24 downto 0);
  signal captured_be_avalon_r   : std_logic_vector(7 downto 0);
  signal captured_be_last_r     : std_logic_vector(7 downto 0);
  
  signal op_id_r : std_logic_vector(7 downto 0);
 
  signal read_data_r : std_logic_vector(63 downto 0);
  signal waitrequest_r : std_logic;
 
  signal data_width_r : std_logic_vector(11 downto 0);
 
  signal wr_cmd_write_r  : std_logic;
  signal wr_data_write_r : std_logic;
  signal rd_cmd_read_r   : std_logic;
  signal rd_data_read_r  : std_logic;
  
  signal burst_rd_cnt : std_logic_vector(3 downto 0);
  signal burst_wr_cnt : std_logic_vector(3 downto 0);

  signal burst_rd_done  : std_logic;
  signal burst_wr_done  : std_logic;

  signal exec_cmd_r : std_logic_vector(65 downto 0);

  alias cmd_operation_type_ra : std_logic is exec_cmd_r(65);
  alias cmd_address_ra : std_logic_vector(24 downto 0) is exec_cmd_r(64 downto 40);
  alias cmd_datawidth_ra : std_logic_vector(11 downto 0) is exec_cmd_r(39 downto 28);
  alias cmd_be_first_ra : std_logic_vector(7 downto 0) is exec_cmd_r(27 downto 20);
  alias cmd_be_last_ra  : std_logic_vector(7 downto 0) is exec_cmd_r(19 downto 12);
  alias cmd_operation_id_ra : std_logic_vector(7 downto 0) is exec_cmd_r(7 downto 0);

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
  read_data_avs   <= read_data_r;

master_fsm: process(clk_80MHz, nRST)
begin
  if nRST = '0' then
    master_state <= IDLE;

  elsif rising_edge(clk_80MHz) then
    case master_state is

      when IDLE =>
        if read_master = '1' then
          if burstenable_master = '1' then
            master_state <= BURST_READ;
          end if;
        end if;
        if read_master = '1' then
          if burstenable_master = '0' then
            master_state <= SINGLE_READ;
          end if;
        end if;
        if write_master = '1' then
          if burstenable_master = '1' then
            master_state <= BURST_WRITE;
          end if;
        end if;
        if write_master = '1' then
          if burstenable_master = '0' then
            master_state <= SINGLE_WRITE;
          end if;
        end if;

      when SINGLE_READ =>
        master_state <= PREPARE_HEADER;

      when SINGLE_WRITE =>
        master_state <= PREPARE_HEADER;

      when BURST_READ =>
        master_state <= PREPARE_HEADER;

      when BURST_WRITE =>
        master_state <= PREPARE_HEADER;

      when PREPARE_HEADER =>
        if wr_cmd_full = '0' then
          master_state <= WRITE_HEADER;
        end if;

      when WRITE_HEADER =>
        if write_master = '1' then
          if burstenable_master = '0' then
            master_state <= WRITE_DATA;
          end if;
        end if;
        if write_master = '1' then
          if burstenable_master = '1' then
            master_state <= BURST_WRITE_DATA;
          end if;
        end if;
        if write_master = '0' then
          master_state <= WAIT_READ_DATA;
        end if;

      when WRITE_DATA =>
        if wr_data_full = '0' then
          master_state <= IDLE;
        end if;

      when BURST_WRITE_DATA =>
        if burst_wr_done = '1' then
          master_state <= IDLE;
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

      when PREPARE_ANSWER =>
        internal_state <= READ_DATA;

      when READ_DATA =>
        if rd_data_empty = '0' then
          internal_state <= IDLE;
        end if;

      when others =>
        internal_state <= IDLE;

    end case;
  end if;
end process;

signals: process(clk_80MHz, nRST)
begin
  if nRST = '0' then

    waitrequest_r    <= '1';
    read_data_r      <= (others => '0');

    wr_cmd_write_r   <= '0';
    wr_data_write_r  <= '0';
    rd_cmd_read_r    <= '0';
    rd_data_read_r   <= '0';

    burst_rd_cnt     <= (others => '0');
    burst_wr_cnt     <= (others => '0');
    burst_rd_done    <= '0';
    burst_wr_done    <= '0';

    exec_cmd_r       <= (others => '0');

  elsif rising_edge(clk_80MHz) then

    wr_cmd_write_r <= '0';
    wr_data_write_r <= '0';
    rd_cmd_read_r <= '0';
    rd_data_read_r <= '0';
    burst_wr_done <= '0';

    if master_state = IDLE then
      captured_addr_avalon_r <= address_master;
    end if;

    if master_state = IDLE then
      captured_be_avalon_r <= byte_enable_master;
    end if;

    if master_state = IDLE then
      captured_be_last_r <= byte_enable_master;
    end if;

    if master_state = IDLE then
      op_id_r <= op_id_r + 1;
    end if;

    if master_state = IDLE then
      if burstenable_master = '1' then
        burst_wr_cnt <= burstcount_master;
      end if;
    end if;

    if master_state = PREPARE_HEADER then
      cmd_operation_type_ra <= write_master;
    end if;

    if master_state = PREPARE_HEADER then
      cmd_address_ra <= captured_addr_avalon_r;
    end if;

    if master_state = PREPARE_HEADER then
      cmd_be_first_ra <= captured_be_avalon_r;
    end if;

    if master_state = PREPARE_HEADER then
      cmd_be_last_ra <= captured_be_last_r;
    end if;

    if master_state = PREPARE_HEADER then
      cmd_operation_id_ra <= op_id_r;
    end if;

    if master_state = PREPARE_HEADER then
      if burstenable_master = '0' then
        cmd_datawidth_ra <= calc_be_params(captured_be_avalon_r);
      end if;
    end if;

    if master_state = PREPARE_HEADER then
      if burstenable_master = '1' then
        cmd_datawidth_ra <= conv_std_logic_vector(
          conv_integer(burstcount_master) * 8, 12);
      end if;
    end if;

    if master_state = WRITE_HEADER then
      if wr_cmd_full = '0' then
        wr_cmd_write_r <= '1';
      end if;
    end if;

    if master_state = WRITE_DATA then
      if wr_data_full = '0' then
        wr_data <= write_data_master;
      end if;
    end if;

    if master_state = WRITE_DATA then
      if wr_data_full = '0' then
        wr_data_write_r <= '1';
      end if;
    end if;

    if master_state = BURST_WRITE_DATA then
      if wr_data_full = '0' then
        wr_data <= write_data_master;
      end if;
    end if;

    if master_state = BURST_WRITE_DATA then
      if wr_data_full = '0' then
        wr_data_write_r <= '1';
      end if;
    end if;

    if master_state = BURST_WRITE_DATA then
      if burst_wr_cnt /= "0000" then
        burst_wr_cnt <= burst_wr_cnt - 1;
      end if;
    end if;

    if master_state = BURST_WRITE_DATA then
      if burst_wr_cnt = "0001" then
        burst_wr_done <= '1';
      end if;
    end if;

    if internal_state = READ_HEADER then
      rd_cmd_read_r <= '1';
    end if;

    if internal_state = READ_DATA then
      if rd_data_empty = '0' then
        rd_data_read_r <= '1';
      end if;
    end if;

    if internal_state = READ_DATA then
      if rd_data_empty = '0' then
        read_data_r <= rd_data;
      end if;
    end if;

    if master_state = SEND_READ_DATA then
      waitrequest_r <= '0';
    end if;

    if master_state = IDLE then
      waitrequest_r <= '1';
    end if;

  end if;
end process;

end architecture rtl;
