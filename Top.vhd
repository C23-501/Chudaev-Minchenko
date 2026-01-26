library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity top is
  port (
    clk_80MHz : in  std_logic;
    nRST      : in  std_logic;
	 wr_cmd_write : out std_logic;
	 wr_data_write : out std_logic;
	 rd_data_read  : out std_logic;
	 rd_cmd_read   : out std_logic
  );
end entity top;

architecture rtl of top is


  signal address_master     : std_logic_vector(24 downto 0);
  signal read_master        : std_logic;
  signal write_master       : std_logic;
  signal write_data_master  : std_logic_vector(63 downto 0);
  signal byte_enable_master : std_logic_vector(7 downto 0);
  signal burstcount_master  : std_logic_vector(4 downto 0);
  signal burstenable_master : std_logic;
  signal read_data_avs      : std_logic_vector(63 downto 0);
  signal waitrequest_avs    : std_logic;
  signal read_data_valid_s  : std_logic;


  signal s_wr_cmd_data  : std_logic_vector(61 downto 0);
  signal s_wr_cmd_write : std_logic;
  signal s_wr_data_data : std_logic_vector(63 downto 0);
  signal s_wr_data_write: std_logic;
  signal s_rd_cmd_data  : std_logic_vector(19 downto 0);
  signal s_rd_cmd_read  : std_logic;
  signal s_rd_data_data : std_logic_vector(63 downto 0);
  signal s_rd_data_read : std_logic;
  

  signal s_rd_cmd_empty : std_logic;
  signal s_rd_data_empty: std_logic;

begin



  u_master : entity work.AvalonMM_Master
    port map (
      clk                => clk_80MHz,
      nRST               => nRST,
      address_master     => address_master,
      read_master        => read_master,
      write_master       => write_master,
      write_data_master  => write_data_master,
      byte_enable_master => byte_enable_master,
      burstcount_master  => burstcount_master,
      burstenable_master => burstenable_master,
      read_data_avs      => read_data_avs,
      waitrequest_avs    => waitrequest_avs,
      scenario_active    => open
    );

  u_slave : entity work.AvalonMM_Slave
    port map (
      clk_80MHz          => clk_80MHz,
      nRST               => nRST,

      address_master     => address_master,
      read_master        => read_master,
      write_master       => write_master,
      write_data_master  => write_data_master,
      byte_enable_master => byte_enable_master,
      burstcount_master  => burstcount_master,
      burstenable_master => burstenable_master,
      read_data_avs      => read_data_avs,
      waitrequest_avs    => waitrequest_avs,
      read_data_valid    => read_data_valid_s,

      wr_cmd_full        => '0',
      wr_cmd             => s_wr_cmd_data,
      wr_cmd_write       => s_wr_cmd_write,
      wr_data_full       => '0',
      wr_data_used       => (others => '0'),
      wr_data            => s_wr_data_data,
      wr_data_write      => s_wr_data_write,
      rd_cmd_empty       => s_rd_cmd_empty,
      rd_cmd             => s_rd_cmd_data,
      rd_cmd_read        => s_rd_cmd_read,
      rd_data_empty      => s_rd_data_empty,
      rd_data            => s_rd_data_data,
      rd_data_read       => s_rd_data_read,
      led_control        => open
    );

  Deadlock_Breaker : process(clk_80MHz, nRST)
  begin
    if nRST = '0' then
      s_rd_cmd_empty <= '1';
      s_rd_data_empty <= '1';
    elsif rising_edge(clk_80MHz) then

      s_rd_cmd_empty <= '1';
      s_rd_data_empty <= '1';

      if s_wr_cmd_write = '1' then
        s_rd_cmd_empty <= '0';
        s_rd_data_empty <= '0';
      end if;
    end if;
  end process Deadlock_Breaker;
  
  wr_cmd_write  <= s_wr_cmd_write;
  wr_data_write <= s_wr_data_write;
  rd_data_read  <= s_rd_data_read;
  rd_cmd_read   <= s_rd_cmd_read;

  s_rd_cmd_data  <= (others => '0');
  s_rd_data_data <= (others => '0');
  


end architecture rtl;

