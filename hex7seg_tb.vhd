library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity hex7seg_tb is
end hex7seg_tb;

architecture testbench of hex7seg_tb is
    component hex7seg
        Generic (
            ACTIVE_LEVEL : std_logic := '0'
        );
        Port ( 
            clk     : in  STD_LOGIC;
            nreset  : in  STD_LOGIC;
            hex_in  : in  STD_LOGIC_VECTOR (7 downto 0);
            seg_out : out STD_LOGIC_VECTOR (13 downto 0)
        );
    end component;

    -- ?????????
    constant CLK_PERIOD : time := 10 ns;
    
    -- ??????? ??? ????????????
    signal clk     : STD_LOGIC := '0';
    signal nreset  : STD_LOGIC := '1';
    signal hex_in  : STD_LOGIC_VECTOR(7 downto 0) := (others => '0');
    signal seg_out : STD_LOGIC_VECTOR(13 downto 0);
    
begin
    -- ????????? ???????????? ??????????
    uut: hex7seg
        generic map (
            ACTIVE_LEVEL => '0'  -- common cathode
        )
        port map (
            clk     => clk,
            nreset  => nreset,
            hex_in  => hex_in,
            seg_out => seg_out
        );

    -- ????????? ????????? ???????
    clk_process : process
    begin
        while true loop
            clk <= '0';
            wait for CLK_PERIOD/2;
            clk <= '1';
            wait for CLK_PERIOD/2;
        end loop;
    end process;

    -- ?????????? ??????? ????????
    stim_proc : process
    begin
        -- ?????
        nreset <= '0';
        wait for CLK_PERIOD*2;
        nreset <= '1';
        wait for CLK_PERIOD;
        
        -- ???????????? ????????? ??????? ????????
        for i in 0 to 15 loop
            hex_in(3 downto 0) <= std_logic_vector(to_unsigned(i, 4));
            hex_in(7 downto 4) <= std_logic_vector(to_unsigned(15-i, 4));
            wait for CLK_PERIOD*5;
        end loop;
        
        -- ?????????? ?????????
        wait;
    end process;
end testbench;