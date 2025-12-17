library ieee;
use ieee.std_logic_1164.all;

entity AvalonMM_SlaveTB is
end entity AvalonMM_SlaveTB;

architecture testbench of AvalonMM_SlaveTB is
  signal s_clk_80MHz : std_logic;
  signal s_nRST : std_logic;
 
  signal s_address_master : std_logic_vector(24 downto 0);
  signal s_read_master : std_logic;
  signal s_write_master : std_logic;
  signal s_write_data_master : std_logic_vector(63 downto 0);
  signal s_byte_enable_master : std_logic_vector(7 downto 0);
  signal s_burstcount_master : std_logic_vector(3 downto 0);
  signal s_read_data_avs : std_logic_vector(63 downto 0);
  signal s_waitrequest_avs : std_logic;
 
  signal s_wr_cmd_full : std_logic;
  signal s_wr_cmd : std_logic_vector(57 downto 0);
  signal s_wr_cmd_write : std_logic;
  signal s_wr_data_full : std_logic;
  signal s_wr_data : std_logic_vector(63 downto 0);
  signal s_wr_data_write : std_logic;
  signal s_rd_cmd_empty : std_logic;
  signal s_rd_cmd : std_logic_vector(23 downto 0);
  signal s_rd_cmd_read : std_logic;
  signal s_rd_data_empty : std_logic;
  signal s_rd_data : std_logic_vector(63 downto 0);
  signal s_rd_data_read : std_logic;
 
  component AvalonMM_Slave
    port (
      clk_80MHz : in std_logic;
      nRST : in std_logic;
     
      address_master : in std_logic_vector(24 downto 0);
      read_master : in std_logic;
      write_master : in std_logic;
      write_data_master : in std_logic_vector(63 downto 0);
      byte_enable_master: in std_logic_vector(7 downto 0);
      burstcount_master : in std_logic_vector(3 downto 0);
     
      read_data_avs : out std_logic_vector(63 downto 0);
      waitrequest_avs : out std_logic;
     
      wr_cmd_full : in std_logic;
      wr_cmd : out std_logic_vector(57 downto 0);
      wr_cmd_write : out std_logic;
     
      wr_data_full : in std_logic;
      wr_data : out std_logic_vector(63 downto 0);
      wr_data_write : out std_logic;
     
      rd_cmd_empty : in std_logic;
      rd_cmd : in std_logic_vector(23 downto 0);
      rd_cmd_read : out std_logic;
     
      rd_data_empty : in std_logic;
      rd_data : in std_logic_vector(63 downto 0);
      rd_data_read : out std_logic
    );
  end component;
 
  component AvalonMM_SlaveTester
    port (
      s_clk_80MHz : out std_logic;
      s_nRST : out std_logic;
     
      s_address_master : out std_logic_vector(24 downto 0);
      s_read_master : out std_logic;
      s_write_master : out std_logic;
      s_write_data_master : out std_logic_vector(63 downto 0);
      s_byte_enable_master : out std_logic_vector(7 downto 0);
      s_burstcount_master : out std_logic_vector(3 downto 0);
     
      s_read_data_avs : in std_logic_vector(63 downto 0);
      s_waitrequest_avs : in std_logic;
     
      s_wr_cmd_full : out std_logic;
      s_wr_cmd : in std_logic_vector(57 downto 0);
      s_wr_cmd_write : in std_logic;
     
      s_wr_data_full : out std_logic;
      s_wr_data : in std_logic_vector(63 downto 0);
      s_wr_data_write : in std_logic;
     
      s_rd_cmd_empty : out std_logic;
      s_rd_cmd : out std_logic_vector(23 downto 0);
      s_rd_cmd_read : in std_logic;
     
      s_rd_data_empty : out std_logic;
      s_rd_data : out std_logic_vector(63 downto 0);
      s_rd_data_read : in std_logic
    );
  end component;
 
begin
  uut: AvalonMM_Slave
    port map (
      clk_80MHz => s_clk_80MHz,
      nRST => s_nRST,
     
      address_master => s_address_master,
      read_master => s_read_master,
      write_master => s_write_master,
      write_data_master => s_write_data_master,
      byte_enable_master=> s_byte_enable_master,
      burstcount_master => s_burstcount_master,
     
      read_data_avs => s_read_data_avs,
      waitrequest_avs => s_waitrequest_avs,
     
      wr_cmd_full => s_wr_cmd_full,
      wr_cmd => s_wr_cmd,
      wr_cmd_write => s_wr_cmd_write,
     
      wr_data_full => s_wr_data_full,
      wr_data => s_wr_data,
      wr_data_write => s_wr_data_write,
     
      rd_cmd_empty => s_rd_cmd_empty,
      rd_cmd => s_rd_cmd,
      rd_cmd_read => s_rd_cmd_read,
     
      rd_data_empty => s_rd_data_empty,
      rd_data => s_rd_data,
      rd_data_read => s_rd_data_read
    );
 
  tester_inst: AvalonMM_SlaveTester
    port map (
      s_clk_80MHz => s_clk_80MHz,
      s_nRST => s_nRST,
     
      s_address_master => s_address_master,
      s_read_master => s_read_master,
      s_write_master => s_write_master,
      s_write_data_master => s_write_data_master,
      s_byte_enable_master => s_byte_enable_master,
      s_burstcount_master => s_burstcount_master,
     
      s_read_data_avs => s_read_data_avs,
      s_waitrequest_avs => s_waitrequest_avs,
     
      s_wr_cmd_full => s_wr_cmd_full,
      s_wr_cmd => s_wr_cmd,
      s_wr_cmd_write => s_wr_cmd_write,
     
      s_wr_data_full => s_wr_data_full,
      s_wr_data => s_wr_data,
      s_wr_data_write => s_wr_data_write,
     
      s_rd_cmd_empty => s_rd_cmd_empty,
      s_rd_cmd => s_rd_cmd,
      s_rd_cmd_read => s_rd_cmd_read,
     
      s_rd_data_empty => s_rd_data_empty,
      s_rd_data => s_rd_data,
      s_rd_data_read => s_rd_data_read
    );
   
end architecture testbench;