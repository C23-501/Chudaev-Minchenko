library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity AvalonMM_Master is
  generic (
    CLK_FREQ_HZ : integer := 80_000_000
  );
  port (
    clk                : in  std_logic;
    nRST               : in  std_logic;
    address_master     : out std_logic_vector(24 downto 0);
    read_master        : out std_logic;
    write_master       : out std_logic;
    write_data_master  : out std_logic_vector(63 downto 0);
    byte_enable_master : out std_logic_vector(7 downto 0);
    burstcount_master  : out std_logic_vector(4 downto 0);
    burstenable_master : out std_logic;
    read_data_avs      : in  std_logic_vector(63 downto 0);
    waitrequest_avs    : in  std_logic;
    
    scenario_active    : out std_logic_vector(3 downto 0)
  );
end entity AvalonMM_Master;

architecture rtl of AvalonMM_Master is
  type state_t is (
    INIT_WAIT,
    S1_SETUP, S1_WRITE, S1_WAIT_DONE,
    S2_DELAY, S2_SETUP, S2_HEADER, S2_DATA,
    S3_DELAY, S3_SETUP, S3_READ, S3_WAIT_DONE,
    S4_DELAY, S4_SETUP, S4_HEADER, S4_WAIT_DONE,
    RESTART_DELAY
  );
  signal state : state_t;

  constant DELAY_CYCLES : integer := 100;
  signal delay_cnt      : integer range 0 to DELAY_CYCLES;
  
  signal burst_word_cnt : integer range 0 to 15;
begin
  process(clk, nRST)
  begin
    if nRST = '0' then
      state <= INIT_WAIT;
      address_master     <= (others => '0');
      read_master        <= '0';
      write_master       <= '0';
      write_data_master  <= (others => '0');
      byte_enable_master <= (others => '0');
      burstcount_master  <= (others => '0');
      burstenable_master <= '0';
      scenario_active    <= "0000";
      delay_cnt          <= 0;
      burst_word_cnt     <= 0;
    elsif rising_edge(clk) then
      
      read_master  <= '0';
      write_master <= '0';
      
      case state is
        when INIT_WAIT =>
          scenario_active <= "0000";
          if delay_cnt = DELAY_CYCLES then
            delay_cnt <= 0;
            state <= S1_SETUP;
          else
            delay_cnt <= delay_cnt + 1;
          end if;

        when S1_SETUP =>
          scenario_active <= "0001";
          address_master     <= std_logic_vector(to_unsigned(16, 25));
          write_data_master  <= x"1111_2222_3333_4444";
          byte_enable_master <= x"FF";
          burstcount_master  <= "00001"; 
          burstenable_master <= '0';
          state <= S1_WRITE;
          
        when S1_WRITE =>
          write_master <= '1';
          if waitrequest_avs = '0' then
            state <= S2_DELAY;
          else
            state <= S1_WAIT_DONE;
          end if;
          
        when S1_WAIT_DONE =>
          write_master <= '1';
          if waitrequest_avs = '0' then
            state <= S2_DELAY;
          end if;

        when S2_DELAY =>
          if delay_cnt = DELAY_CYCLES then
            delay_cnt <= 0;
            state <= S2_SETUP;
          else
            delay_cnt <= delay_cnt + 1;
          end if;

        when S2_SETUP =>
          scenario_active <= "0010";
          address_master     <= std_logic_vector(to_unsigned(32, 25));
          burstcount_master  <= "00100";
          burstenable_master <= '1';
          byte_enable_master <= x"FF";
          write_data_master  <= x"AAAA_AAAA_AAAA_AAAA"; 
          burst_word_cnt     <= 1;
          state <= S2_HEADER;

        when S2_HEADER =>
          write_master       <= '1';
          burstenable_master <= '1';
          if waitrequest_avs = '0' then
             state <= S2_DATA;
          end if;

        when S2_DATA =>
          burstenable_master <= '0'; 
          write_master       <= '1';
          if burst_word_cnt = 1 then write_data_master <= x"BBBB_BBBB_BBBB_BBBB"; end if;
          if burst_word_cnt = 2 then write_data_master <= x"CCCC_CCCC_CCCC_CCCC"; end if;
          if burst_word_cnt = 3 then write_data_master <= x"DDDD_DDDD_DDDD_DDDD"; end if;
          if waitrequest_avs = '0' then
             if burst_word_cnt = 3 then
                state <= S3_DELAY;
             else
                burst_word_cnt <= burst_word_cnt + 1;
             end if;
          end if;

        when S3_DELAY =>
          if delay_cnt = DELAY_CYCLES then
            delay_cnt <= 0;
            state <= S3_SETUP;
          else
            delay_cnt <= delay_cnt + 1;
          end if;

        when S3_SETUP =>
          scenario_active <= "0011";
          address_master     <= std_logic_vector(to_unsigned(16, 25));
          byte_enable_master <= x"FF";
          burstcount_master  <= "00001";
          burstenable_master <= '0';
          state <= S3_READ;
          
        when S3_READ =>
          read_master <= '1';
          if waitrequest_avs = '0' then
            state <= S4_DELAY;
          else
            state <= S3_WAIT_DONE;
          end if;
          
        when S3_WAIT_DONE =>
          read_master <= '1';
          if waitrequest_avs = '0' then
            state <= S4_DELAY;
          end if;

        when S4_DELAY =>
          if delay_cnt = DELAY_CYCLES then
            delay_cnt <= 0;
            state <= S4_SETUP;
          else
            delay_cnt <= delay_cnt + 1;
          end if;

        when S4_SETUP =>
          scenario_active <= "0100";
          address_master     <= std_logic_vector(to_unsigned(32, 25));
          burstcount_master  <= "00100";
          burstenable_master <= '1';
          byte_enable_master <= x"FF";
          state <= S4_HEADER;
          
        when S4_HEADER =>
          read_master        <= '1';
          burstenable_master <= '1';
          if waitrequest_avs = '0' then
            state <= RESTART_DELAY;
          else
            state <= S4_WAIT_DONE;
          end if;

        when S4_WAIT_DONE =>
          read_master        <= '1';
          burstenable_master <= '1';
          if waitrequest_avs = '0' then
             state <= RESTART_DELAY;
          end if;

        when RESTART_DELAY =>
          scenario_active <= "1111";
          if delay_cnt = DELAY_CYCLES then
            delay_cnt <= 0;
            state <= S1_SETUP;
          else
            delay_cnt <= delay_cnt + 1;
          end if;
      end case;
    end if;
  end process;
end architecture rtl;

