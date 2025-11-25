library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity AvalonMM_Slave is
  generic (
    ADDR_WIDTH       : integer := 25;
    DATA_WIDTH       : integer := 32;
    BURSTCOUNT_WIDTH : integer := 4
  );
  port (
    clk         : in  std_logic;
    reset_n     : in  std_logic;

    address     : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
    read        : in  std_logic;
    write       : in  std_logic;
    writedata   : in  std_logic_vector(DATA_WIDTH-1 downto 0);
    byteenable  : in  std_logic_vector((DATA_WIDTH/8)-1 downto 0);
    burstcount  : in  std_logic_vector(BURSTCOUNT_WIDTH-1 downto 0);

    readdata    : out std_logic_vector(DATA_WIDTH-1 downto 0);
    waitrequest : out std_logic
  );
end entity;

architecture rtl of AvalonMM_Slave is

  constant BYTEEN_WIDTH : integer := DATA_WIDTH / 8;
  constant CMD_WIDTH    : integer := 1 + ADDR_WIDTH + 16 + BYTEEN_WIDTH + 8;
  constant RESP_WIDTH   : integer := 8 + 16;

  -- Функции
  function count_ones(be : std_logic_vector) return integer is
    variable cnt : integer := 0;
  begin
    for i in be'range loop
      if be(i) = '1' then cnt := cnt + 1; end if;
    end loop;
    return cnt;
  end function;

  function lowest_enabled_byte(be : std_logic_vector) return integer is
  begin
    for i in be'low to be'high loop
      if be(i) = '1' then return i; end if;
    end loop;
    return 0;
  end function;

  -- FIFO к бэкенду
  signal cmd_data      : std_logic_vector(CMD_WIDTH-1 downto 0);
  signal cmd_write     : std_logic;
  signal cmd_full      : std_logic;

  signal wr_data       : std_logic_vector(DATA_WIDTH-1 downto 0);
  signal wr_data_write : std_logic;
  signal wr_data_full  : std_logic;

  signal resp_data     : std_logic_vector(RESP_WIDTH-1 downto 0);
  signal resp_read     : std_logic;
  signal resp_empty    : std_logic;

  signal rd_data       : std_logic_vector(DATA_WIDTH-1 downto 0);
  signal rd_data_read  : std_logic;
  signal rd_data_empty : std_logic;

  -- FSM для работы с мастером
  type master_state_t is (IDLE, READ_BURST, WRITE_BURST);
  signal master_state_r     : master_state_t := IDLE;

  -- FSM для работы с внутренней логикой
  type internal_state_t is (INT_IDLE, WR_CMD_SENT, RD_CMD_SENT, RD_WAIT_DATA);
  signal internal_state_r   : internal_state_t := INT_IDLE;

  -- Захваченные параметры транзакции
  signal captured_addr_r    : std_logic_vector(ADDR_WIDTH-1 downto 0) := (others => '0');
  signal captured_be_r      : std_logic_vector(BYTEEN_WIDTH-1 downto 0) := (others => '0');
  signal captured_burst_r   : integer := 0;
  signal captured_byte_offset_r : integer := 0;
  signal captured_active_bytes_r : integer := 0;

  -- Регистры
  signal op_id_r            : unsigned(7 downto 0) := (others => '0');
  signal master_beats_remaining_r : integer := 0;
  signal internal_beats_remaining_r : integer := 0;
  signal remaining_bytes_r  : unsigned(15 downto 0) := (others => '0');
  
  -- Счетчики для отслеживания прогресса
  signal write_beats_sent_r     : integer := 0;
  signal read_beats_received_r  : integer := 0;
  
  signal readdata_r         : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');
  signal waitrequest_r      : std_logic := '1';

begin

  readdata    <= readdata_r;
  waitrequest <= waitrequest_r;

  -- FSM для работы с Avalon-MM мастером
  master_fsm: process(clk, reset_n)
    variable burst_len      : integer;
    variable active_bytes   : integer;
    variable byte_offset    : integer;
  begin
    if reset_n = '0' then
      master_state_r           <= IDLE;
      master_beats_remaining_r <= 0;
      write_beats_sent_r       <= 0;
      read_beats_received_r    <= 0;
      readdata_r               <= (others => '0');
      waitrequest_r            <= '1';
      
      captured_addr_r          <= (others => '0');
      captured_be_r            <= (others => '0');
      captured_burst_r         <= 0;
      captured_byte_offset_r   <= 0;
      captured_active_bytes_r  <= 0;

      wr_data_write <= '0';
      rd_data_read  <= '0';

    elsif rising_edge(clk) then
      -- Default values
      waitrequest_r <= '1';
      wr_data_write <= '0';
      rd_data_read  <= '0';

      burst_len     := to_integer(unsigned(burstcount));
      if burst_len = 0 then burst_len := 1; end if;
      active_bytes  := count_ones(byteenable);
      byte_offset   := lowest_enabled_byte(byteenable);

      case master_state_r is

        when IDLE =>
          if write = '1' and internal_state_r = INT_IDLE then

            captured_addr_r <= address;
            captured_be_r <= byteenable;
            captured_burst_r <= burst_len;
            captured_byte_offset_r <= byte_offset;
            captured_active_bytes_r <= active_bytes;
            
            master_state_r <= WRITE_BURST;
            master_beats_remaining_r <= burst_len;
            write_beats_sent_r <= 0;
            
            if wr_data_full = '0' then
              waitrequest_r <= '0';
            end if;

          elsif read = '1' and internal_state_r = INT_IDLE then
            captured_addr_r <= address;
            captured_be_r <= byteenable;
            captured_burst_r <= burst_len;
            captured_byte_offset_r <= byte_offset;
            captured_active_bytes_r <= active_bytes;
            
            master_state_r <= READ_BURST;
            master_beats_remaining_r <= burst_len;
            read_beats_received_r <= 0;
            

            if rd_data_empty = '0' then
              waitrequest_r <= '0';
            end if;
          end if;

        when WRITE_BURST =>

          if wr_data_full = '0' and master_beats_remaining_r > 0 then
            waitrequest_r <= '0';
          else
            waitrequest_r <= '1';
          end if;


          if write = '1' and waitrequest_r = '0' then

            wr_data <= std_logic_vector(shift_right(unsigned(writedata), captured_byte_offset_r * 8));
            wr_data_write <= '1';
            write_beats_sent_r <= write_beats_sent_r + 1;
            
            if master_beats_remaining_r > 0 then
              master_beats_remaining_r <= master_beats_remaining_r - 1;
            end if;
            

            if master_beats_remaining_r = 1 then
              master_state_r <= IDLE;
            end if;
          end if;


          if write = '0' and master_beats_remaining_r > 0 then
            master_state_r <= IDLE;
          end if;

        when READ_BURST =>

          if rd_data_empty = '0' and master_beats_remaining_r > 0 then
            waitrequest_r <= '0';
          else
            waitrequest_r <= '1';
          end if;


          if read = '1' and waitrequest_r = '0' then

            rd_data_read <= '1';
            readdata_r <= std_logic_vector(shift_left(unsigned(rd_data), captured_byte_offset_r * 8));
            read_beats_received_r <= read_beats_received_r + 1;
            
            if master_beats_remaining_r > 0 then
              master_beats_remaining_r <= master_beats_remaining_r - 1;
            end if;
            
            if master_beats_remaining_r = 1 then
              master_state_r <= IDLE;
            end if;
          end if;


          if read = '0' and master_beats_remaining_r > 0 then
            master_state_r <= IDLE;
          end if;

      end case;
    end if;
  end process;

  -- FSM для работы с внутренней логикой
  internal_fsm: process(clk, reset_n)
    variable total_bytes_v  : unsigned(15 downto 0);
    variable adj_addr       : unsigned(ADDR_WIDTH-1 downto 0);
  begin
    if reset_n = '0' then
      internal_state_r <= INT_IDLE;
      internal_beats_remaining_r <= 0;
      remaining_bytes_r <= (others => '0');
      op_id_r <= (others => '0');
      
      cmd_write <= '0';
      resp_read <= '0';

    elsif rising_edge(clk) then
      cmd_write <= '0';
      resp_read <= '0';

      total_bytes_v := to_unsigned(captured_active_bytes_r * captured_burst_r, 16);
      adj_addr := unsigned(captured_addr_r) + to_unsigned(captured_byte_offset_r, ADDR_WIDTH);

      case internal_state_r is

        when INT_IDLE =>
          if master_state_r = WRITE_BURST and cmd_full = '0' then
            cmd_data <= '1' &
                       std_logic_vector(adj_addr) &
                       std_logic_vector(total_bytes_v) &
                       captured_be_r &
                       std_logic_vector(op_id_r);
            cmd_write <= '1';
            op_id_r <= op_id_r + 1;
            internal_state_r <= WR_CMD_SENT;

          elsif master_state_r = READ_BURST and cmd_full = '0' then
            cmd_data <= '0' &
                       std_logic_vector(adj_addr) &
                       std_logic_vector(total_bytes_v) &
                       captured_be_r &
                       std_logic_vector(op_id_r);
            cmd_write <= '1';
            op_id_r <= op_id_r + 1;
            internal_state_r <= RD_CMD_SENT;
          end if;

        when WR_CMD_SENT =>
          if master_state_r /= WRITE_BURST then
            internal_state_r <= INT_IDLE;
          elsif write_beats_sent_r >= captured_burst_r then
            internal_state_r <= INT_IDLE;
          end if;

        when RD_CMD_SENT =>
          if resp_empty = '0' then
            resp_read <= '1';
            remaining_bytes_r <= unsigned(resp_data(15 downto 0));
            
            if remaining_bytes_r = 0 then
              internal_state_r <= INT_IDLE;
            else
              internal_state_r <= RD_WAIT_DATA;
              if captured_active_bytes_r > 0 then
                internal_beats_remaining_r <= (to_integer(remaining_bytes_r) + captured_active_bytes_r - 1) / captured_active_bytes_r;
              else
                internal_beats_remaining_r <= 0;
              end if;
            end if;
          end if;

          if master_state_r /= READ_BURST then
            internal_state_r <= INT_IDLE;
          end if;

        when RD_WAIT_DATA =>
          if master_state_r /= READ_BURST then
            internal_state_r <= INT_IDLE;
          elsif read_beats_received_r >= captured_burst_r then
            internal_state_r <= INT_IDLE;
          end if;

      end case;
    end if;
  end process;

end architecture rtl;