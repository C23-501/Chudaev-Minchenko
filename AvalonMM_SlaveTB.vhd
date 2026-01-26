library ieee;
use ieee.std_logic_1164.all;

entity AvalonMM_SlaveTB is
end entity;

architecture sim of AvalonMM_SlaveTB is

    signal clk      : std_logic := '0';
    signal nRST     : std_logic;
    signal rst_fifo : std_logic;

    signal avs_read_data_valid : std_logic;
    signal avs_addr        : std_logic_vector(24 downto 0);
    signal avs_read        : std_logic;
    signal avs_write       : std_logic;
    signal avs_write_data  : std_logic_vector(63 downto 0);
    signal avs_read_data   : std_logic_vector(63 downto 0);
    signal avs_byte_enable : std_logic_vector(7 downto 0);
    signal avs_burst_count : std_logic_vector(4 downto 0);
    signal avs_burst_en    : std_logic;
    signal avs_waitrequest : std_logic;

    signal s_wr_cmd_data   : std_logic_vector(61 downto 0);
    signal s_wr_cmd_val    : std_logic;
    signal s_wr_cmd_full   : std_logic;
    signal b_wr_cmd_data   : std_logic_vector(61 downto 0);
    signal b_wr_cmd_rd     : std_logic;
    signal b_wr_cmd_empty  : std_logic;

    signal s_wr_data_data  : std_logic_vector(63 downto 0);
    signal s_wr_data_val   : std_logic;
    signal s_wr_data_full  : std_logic;
    signal s_wr_data_used  : std_logic_vector(9 downto 0);
    signal b_wr_data_data  : std_logic_vector(63 downto 0);
    signal b_wr_data_rd    : std_logic;
    signal b_wr_data_empty : std_logic;

    signal b_rd_cmd_data   : std_logic_vector(19 downto 0);
    signal b_rd_cmd_val    : std_logic;
    signal b_rd_cmd_full   : std_logic;
    signal s_rd_cmd_data   : std_logic_vector(19 downto 0);
    signal s_rd_cmd_rd     : std_logic;
    signal s_rd_cmd_empty  : std_logic;

    signal b_rd_data_data  : std_logic_vector(63 downto 0);
    signal b_rd_data_val   : std_logic;
    signal b_rd_data_full  : std_logic;
    signal s_rd_data_data  : std_logic_vector(63 downto 0);
    signal s_rd_data_rd    : std_logic;
    signal s_rd_data_empty : std_logic;

begin

    clk      <= not clk after 6.25 ns;
    rst_fifo <= not nRST;

    FIFO_WR_CMD: entity work.FIFO 
        generic map ( DATA_WIDTH => 62 )
        port map (
            wr_clk   => clk,
            wr_reset => rst_fifo,
            data_i   => s_wr_cmd_data,
            wr_en    => s_wr_cmd_val,
            wr_full  => s_wr_cmd_full,
            wr_used  => open,
            wr_empty => open,
            rd_clk   => clk,
            rd_reset => rst_fifo,
            data_o   => b_wr_cmd_data,
            rd_en    => b_wr_cmd_rd,
            rd_empty => b_wr_cmd_empty,
            rd_full  => open,
            rd_used  => open
        );

    FIFO_WR_DATA: entity work.FIFO 
        generic map ( DATA_WIDTH => 64 ) 
        port map (
            wr_clk   => clk,
            wr_reset => rst_fifo,
            data_i   => s_wr_data_data,
            wr_en    => s_wr_data_val,
            wr_full  => s_wr_data_full,
            wr_used  => s_wr_data_used,
            wr_empty => open,
            rd_clk   => clk,
            rd_reset => rst_fifo,
            data_o   => b_wr_data_data,
            rd_en    => b_wr_data_rd,
            rd_empty => b_wr_data_empty,
            rd_full  => open,
            rd_used  => open
        );

    FIFO_RD_CMD: entity work.FIFO 
        generic map ( DATA_WIDTH => 20 )
        port map (
            wr_clk   => clk,
            wr_reset => rst_fifo,
            data_i   => b_rd_cmd_data,
            wr_en    => b_rd_cmd_val,
            wr_full  => b_rd_cmd_full,
            wr_used  => open,
            wr_empty => open,
            rd_clk   => clk,
            rd_reset => rst_fifo,
            data_o   => s_rd_cmd_data,
            rd_en    => s_rd_cmd_rd,
            rd_empty => s_rd_cmd_empty,
            rd_full  => open,
            rd_used  => open
        );

    FIFO_RD_DATA: entity work.FIFO 
        generic map ( DATA_WIDTH => 64 ) 
        port map (
            wr_clk   => clk,
            wr_reset => rst_fifo,
            data_i   => b_rd_data_data,
            wr_en    => b_rd_data_val,
            wr_full  => b_rd_data_full,
            wr_used  => open,
            wr_empty => open,
            rd_clk   => clk,
            rd_reset => rst_fifo,
            data_o   => s_rd_data_data,
            rd_en    => s_rd_data_rd,
            rd_empty => s_rd_data_empty,
            rd_full  => open,
            rd_used  => open
        );

    DUT: entity work.AvalonMM_Slave 
        port map (
            clk_80MHz          => clk,
            nRST               => nRST,
            address_master     => avs_addr,
            read_master        => avs_read,
            write_master       => avs_write,
            write_data_master  => avs_write_data,
            byte_enable_master => avs_byte_enable,
            burstcount_master  => avs_burst_count,
            burstenable_master => avs_burst_en,
            read_data_avs      => avs_read_data,
            read_data_valid    => avs_read_data_valid,
            waitrequest_avs    => avs_waitrequest,
            wr_cmd_full        => s_wr_cmd_full,
            wr_cmd             => s_wr_cmd_data,
            wr_cmd_write       => s_wr_cmd_val,
            wr_data_full       => s_wr_data_full,
            wr_data_used       => s_wr_data_used,
            wr_data            => s_wr_data_data,
            wr_data_write      => s_wr_data_val,
            rd_cmd_empty       => s_rd_cmd_empty,
            rd_cmd             => s_rd_cmd_data,
            rd_cmd_read        => s_rd_cmd_rd,
            rd_data_empty      => s_rd_data_empty,
            rd_data            => s_rd_data_data,
            rd_data_read       => s_rd_data_rd,
            led_control        => open
        );

    MASTER: entity work.AvalonMM_SlaveTester 
        port map (
            clk                => clk,
            nRST               => nRST,
            address_master     => avs_addr,
            read_master        => avs_read,
            read_data_valid    => avs_read_data_valid,
            write_master       => avs_write,
            write_data_master  => avs_write_data,
            byte_enable_master => avs_byte_enable,
            burstcount_master  => avs_burst_count,
            burstenable_master => avs_burst_en,
            read_data_avs      => avs_read_data,
            waitrequest_avs    => avs_waitrequest,
            b_wr_cmd_empty     => b_wr_cmd_empty,
            b_wr_cmd_rd_en     => b_wr_cmd_rd,
            b_wr_cmd_data      => b_wr_cmd_data,
            b_wr_data_empty    => b_wr_data_empty,
            b_wr_data_rd_en    => b_wr_data_rd,
            b_wr_data_data     => b_wr_data_data,
            b_rd_cmd_full      => b_rd_cmd_full,
            b_rd_cmd_wr_en     => b_rd_cmd_val,
            b_rd_cmd_data      => b_rd_cmd_data,
            b_rd_data_full     => b_rd_data_full,
            b_rd_data_wr_en    => b_rd_data_val,
            b_rd_data_data     => b_rd_data_data
        );

end architecture;