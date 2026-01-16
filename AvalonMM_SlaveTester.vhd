library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.AvalonMM_SlavePackage.all;

entity AvalonMM_SlaveTester is
  port (
    clk : in std_logic;
    nRST : out std_logic;

    address_master : out t_addr;
    read_master    : out std_logic;
    write_master   : out std_logic;
    write_data_master : out t_data;
    byte_enable_master : out t_be;
    burstcount_master  : out t_bc;
    burstenable_master : out std_logic;

    read_data_avs   : in t_data;
    read_data_valid : in std_logic;

    waitrequest_avs : in std_logic;

    b_wr_cmd_empty : in std_logic;
    b_wr_cmd_rd_en : out std_logic;
    b_wr_cmd_data  : in std_logic_vector(57 downto 0);

    b_wr_data_empty : in std_logic;
    b_wr_data_rd_en : out std_logic;
    b_wr_data_data  : in std_logic_vector(63 downto 0);

    b_rd_cmd_full : in std_logic;
    b_rd_cmd_wr_en : out std_logic;
    b_rd_cmd_data  : out std_logic_vector(33 downto 0);

    b_rd_data_full : in std_logic;
    b_rd_data_wr_en : out std_logic;
    b_rd_data_data  : out std_logic_vector(63 downto 0)
  );
end entity;

architecture sim of AvalonMM_SlaveTester is

  type t_be_array is array (natural range <>) of std_logic_vector(7 downto 0);
  constant TEST_BE_VECTORS : t_be_array := (
    x"01", x"02", x"04", x"08", x"10", x"20", x"40", x"80",
    x"18", x"3C", x"7E",
    x"F8", x"7C", x"1F",
    x"FF"
  );

  signal backend_paused : std_logic := '0';

begin

  process
    variable dummy_read : t_data := (others => '0');

    -- Процедура очистки шины
    procedure bus_clear is
    begin
      read_master <= '0';
      write_master <= '0';
      address_master <= (others => '0');
      write_data_master <= (others => '0');
      byte_enable_master <= (others => '0');
      burstcount_master <= std_logic_vector(to_unsigned(1, t_bc'length));
      burstenable_master <= '0';
      wait until rising_edge(clk);
    end procedure;

	 
  begin
    address_master <= (others => '0');
    read_master <= '0';
    write_master <= '0';
    write_data_master <= (others => '0');
    byte_enable_master <= (others => '0');
    burstcount_master <= (others => '0');
    burstenable_master <= '0';
    nRST <= '0';
    backend_paused <= '0';
    wait for 100 ns;
    nRST <= '1';
    wait until rising_edge(clk);

    report "SCENARIO 1: Single Writes";
    for i in TEST_BE_VECTORS'range loop
      avalon_single_write(
        clk => clk,
        waitrequest => waitrequest_avs,
        address => address_master,
        write => write_master,
        read => read_master,
        writedata => write_data_master,
        byteenable => byte_enable_master,
        addr => std_logic_vector(to_unsigned(i, 25)),
        data => x"AAAA_BBBB_CCCC_DD" & TEST_BE_VECTORS(i),
        be => TEST_BE_VECTORS(i)
      );
    end loop;
	 
    nRST <= '0';
    backend_paused <= '0';
    wait for 100 ns;
    nRST <= '1';
    wait until rising_edge(clk);

    report "SCENARIO 2: Burst Writes (Burstcount=4)";
    for i in 0 to 2 loop
      address_master <= std_logic_vector(to_unsigned(i * 8, 25));
      burstcount_master <= "0100";
      burstenable_master <= '1';
      write_master <= '1';
      byte_enable_master <= TEST_BE_VECTORS(i);
      write_data_master <= x"B1B1_B1B1_0000_00" & TEST_BE_VECTORS(i);

      wait until rising_edge(clk) and waitrequest_avs = '0';
      burstenable_master <= '0';

      for burst_step in 2 to 4 loop
        write_data_master <= std_logic_vector(to_unsigned(burst_step, 64));
        wait until rising_edge(clk) and waitrequest_avs = '0';
      end loop;

      write_master <= '0';
      wait until rising_edge(clk);
		
    end loop;
    bus_clear;

	 
    nRST <= '0';
    backend_paused <= '0';
    wait for 100 ns;
    nRST <= '1';
    wait until rising_edge(clk);
	 
    report "SCENARIO 3: Burst Writes (Burstcount=16)";
    for i in 0 to 2 loop
      address_master <= std_logic_vector(to_unsigned(i * 8, 25));
      burstcount_master <= "1111";
      burstenable_master <= '1';
      write_master <= '1';
      byte_enable_master <= TEST_BE_VECTORS(i);
      write_data_master <= x"B1B1_B1B1_0000_00" & TEST_BE_VECTORS(i);

      wait until rising_edge(clk) and waitrequest_avs = '0';
      burstenable_master <= '0';

      for burst_step in 2 to 16 loop
        write_data_master <= std_logic_vector(to_unsigned(burst_step, 64));
        wait until rising_edge(clk) and waitrequest_avs = '0';
      end loop;

      write_master <= '0';
      wait until rising_edge(clk);
		
		
    end loop;
    bus_clear;

	 
    nRST <= '0';
    backend_paused <= '0';
    wait for 100 ns;
    nRST <= '1';
    wait until rising_edge(clk);
	 
    report "SCENARIO 4: Single Reads";
    for i in TEST_BE_VECTORS'range loop
      avalon_single_read(
        clk => clk,
        waitrequest => waitrequest_avs,
        readdata => read_data_avs,
        address => address_master,
        read => read_master,
        write => write_master,
        byteenable => byte_enable_master,
        addr => std_logic_vector(to_unsigned(i, 25)),
        be => TEST_BE_VECTORS(i),
        data_out => dummy_read
      );
    end loop;

	 
    nRST <= '0';
    backend_paused <= '0';
    wait for 100 ns;
    nRST <= '1';
    wait until rising_edge(clk);

	 report "SCENARIO 5: Burst Reads (Burstcount=4)";
    for i in 0 to 2 loop
      address_master <= std_logic_vector(to_unsigned(i * 8, 25));
      burstcount_master <= "0100";
      burstenable_master <= '1';
      read_master <= '1';
      byte_enable_master <= TEST_BE_VECTORS(i);
      wait until rising_edge(clk) and waitrequest_avs = '0';
      burstenable_master <= '0';
      for burst_step in 2 to 4 loop
        wait until rising_edge(clk) and waitrequest_avs = '0';
      end loop;
      read_master <= '0';
      wait until rising_edge(clk);
    end loop;
	 
    nRST <= '0';
    backend_paused <= '0';
    wait for 100 ns;
    nRST <= '1';
    wait until rising_edge(clk);
	 
    
    report "SCENARIO 6: Burst Reads (Burstcount=16)";
    for i in 0 to 2 loop
      address_master <= std_logic_vector(to_unsigned(i * 8, 25));
      burstcount_master <= "1111";
      burstenable_master <= '1';
      read_master <= '1';
      byte_enable_master <= TEST_BE_VECTORS(i);
      wait until rising_edge(clk) and waitrequest_avs = '0';
      burstenable_master <= '0';
      for burst_step in 2 to 16 loop
        wait until rising_edge(clk) and waitrequest_avs = '0';
      end loop;
      read_master <= '0';
      wait until rising_edge(clk);
		
    end loop;
	 
	 
	 
    wait for 100 ns;
    backend_paused <= '0';
    wait for 500 ns;
    report "--- ALL TEST SCENARIOS COMPLETED ---" severity failure;

  end process;

  process(clk)
    variable v_wr_cmd_rd  : std_logic := '0';
    variable v_wr_data_rd : std_logic := '0';
    variable v_rd_cmd_wr  : std_logic := '0';
    variable v_rd_data_wr : std_logic := '0';
    variable delay_cnt    : integer range 0 to 15 := 0;
  begin
    if rising_edge(clk) then
      v_wr_cmd_rd  := '0';
      v_wr_data_rd := '0';
      v_rd_cmd_wr  := '0';
      v_rd_data_wr := '0';

      if backend_paused = '0' then
        if delay_cnt > 0 then
          delay_cnt := delay_cnt - 1;
        elsif b_wr_cmd_empty = '0' then
          delay_cnt := 7;
          v_wr_cmd_rd := '1';

          if b_wr_cmd_data(57) = '1' then
            if b_wr_data_empty = '0' then
              v_wr_data_rd := '1';
            end if;
          else
            if b_rd_data_full = '0' and b_rd_cmd_full = '0' then
              b_rd_data_data <= x"BEEF_0000_BEEF_1111";
              v_rd_data_wr := '1';
              b_rd_cmd_data <= (others => '1');
              v_rd_cmd_wr := '1';
            end if;
          end if;

        else
          delay_cnt := 0;
        end if;

        b_wr_cmd_rd_en  <= v_wr_cmd_rd;
        b_wr_data_rd_en <= v_wr_data_rd;
        b_rd_cmd_wr_en  <= v_rd_cmd_wr;
        b_rd_data_wr_en <= v_rd_data_wr;
      end if;
    end if;
  end process;

end architecture;
