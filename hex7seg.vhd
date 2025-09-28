library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity hex7seg is
    Generic (
        ACTIVE_LEVEL : std_logic := '0'  
    );
    Port ( 
        clk      : in  STD_LOGIC;
        nreset   : in  STD_LOGIC;
        hex_in   : in  STD_LOGIC_VECTOR (7 downto 0);  
        seg_out  : out STD_LOGIC_VECTOR (13 downto 0)  
    );
end hex7seg;

architecture Behavioral of hex7seg is
    signal seg_outr : STD_LOGIC_VECTOR(13 downto 0);  

begin
    process(clk, nreset)
    begin
        if nreset = '0' then
            seg_outr <= (others => not ACTIVE_LEVEL);  
        elsif rising_edge(clk) then
            if    hex_in(3 downto 0) = "0000" then seg_outr(6 downto 0) <= "1000000";
            elsif hex_in(3 downto 0) = "0001" then seg_outr(6 downto 0) <= "1111001";
            elsif hex_in(3 downto 0) = "0010" then seg_outr(6 downto 0) <= "0100100";
            elsif hex_in(3 downto 0) = "0011" then seg_outr(6 downto 0) <= "0110000";
            elsif hex_in(3 downto 0) = "0100" then seg_outr(6 downto 0) <= "0011001";
            elsif hex_in(3 downto 0) = "0101" then seg_outr(6 downto 0) <= "0010010";
            elsif hex_in(3 downto 0) = "0110" then seg_outr(6 downto 0) <= "0000010";
            elsif hex_in(3 downto 0) = "0111" then seg_outr(6 downto 0) <= "1111000";
            elsif hex_in(3 downto 0) = "1000" then seg_outr(6 downto 0) <= "0000000";
            elsif hex_in(3 downto 0) = "1001" then seg_outr(6 downto 0) <= "0010000";
            elsif hex_in(3 downto 0) = "1010" then seg_outr(6 downto 0) <= "0001000";
            elsif hex_in(3 downto 0) = "1011" then seg_outr(6 downto 0) <= "0000011";
            elsif hex_in(3 downto 0) = "1100" then seg_outr(6 downto 0) <= "1000110";
            elsif hex_in(3 downto 0) = "1101" then seg_outr(6 downto 0) <= "0100001";
            elsif hex_in(3 downto 0) = "1110" then seg_outr(6 downto 0) <= "0000110";
            elsif hex_in(3 downto 0) = "1111" then seg_outr(6 downto 0) <= "0001110";
            else                                   seg_outr(6 downto 0) <= "1111111";
            end if;

            if    hex_in(7 downto 4) = "0000" then seg_outr(13 downto 7) <= "1000000";
            elsif hex_in(7 downto 4) = "0001" then seg_outr(13 downto 7) <= "1111001";
            elsif hex_in(7 downto 4) = "0010" then seg_outr(13 downto 7) <= "0100100";
            elsif hex_in(7 downto 4) = "0011" then seg_outr(13 downto 7) <= "0110000";
            elsif hex_in(7 downto 4) = "0100" then seg_outr(13 downto 7) <= "0011001";
            elsif hex_in(7 downto 4) = "0101" then seg_outr(13 downto 7) <= "0010010";
            elsif hex_in(7 downto 4) = "0110" then seg_outr(13 downto 7) <= "0000010";
            elsif hex_in(7 downto 4) = "0111" then seg_outr(13 downto 7) <= "1111000";
            elsif hex_in(7 downto 4) = "1000" then seg_outr(13 downto 7) <= "0000000";
            elsif hex_in(7 downto 4) = "1001" then seg_outr(13 downto 7) <= "0010000";
            elsif hex_in(7 downto 4) = "1010" then seg_outr(13 downto 7) <= "0001000";
            elsif hex_in(7 downto 4) = "1011" then seg_outr(13 downto 7) <= "0000011";
            elsif hex_in(7 downto 4) = "1100" then seg_outr(13 downto 7) <= "1000110";
            elsif hex_in(7 downto 4) = "1101" then seg_outr(13 downto 7) <= "0100001";
            elsif hex_in(7 downto 4) = "1110" then seg_outr(13 downto 7) <= "0000110";
            elsif hex_in(7 downto 4) = "1111" then seg_outr(13 downto 7) <= "0001110";
            else                                   seg_outr(13 downto 7) <= "1111111";
            end if;
        end if;
    end process;

    seg_out <= seg_outr when ACTIVE_LEVEL = '0' else not seg_outr;

end Behavioral;