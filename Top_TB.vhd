library ieee;
use ieee.std_logic_1164.all;

entity top_tb is
end entity top_tb;

architecture behavioral of top_tb is
    component top is
        port (
            clk_80MHz : in  std_logic;
            nRST      : in  std_logic;
            wr_cmd_write : out std_logic;
	         wr_data_write : out std_logic;
	         rd_data_read  : out std_logic;
	         rd_cmd_read   : out std_logic
        );
    end component top;

    signal tb_clk_80MHz : std_logic := '0';
    signal tb_nRST      : std_logic := '0';

    signal s_wr_cmd_write  : std_logic;
    signal s_wr_data_write : std_logic;
    signal s_rd_data_read  : std_logic;
    signal s_rd_cmd_read   : std_logic;

    constant CLK_PERIOD : time := 12.5 ns;

begin
    uut: top
        port map (
            clk_80MHz => tb_clk_80MHz,
            nRST      => tb_nRST,
				
            wr_cmd_write  => s_wr_cmd_write,
            wr_data_write => s_wr_data_write,
            rd_data_read  => s_rd_data_read,
            rd_cmd_read   => s_rd_cmd_read
        );

    clk_process : process
    begin
        tb_clk_80MHz <= '0';
        wait for CLK_PERIOD / 2;
        tb_clk_80MHz <= '1';
        wait for CLK_PERIOD / 2;
    end process clk_process;

    stim_proc: process
    begin
        tb_nRST <= '0';
        wait until rising_edge(tb_clk_80MHz);
		  wait until rising_edge(tb_clk_80MHz);
		  wait until rising_edge(tb_clk_80MHz);

        tb_nRST <= '1';
        

        wait;
    end process stim_proc;

end architecture behavioral;
