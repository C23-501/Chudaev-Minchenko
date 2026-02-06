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
    burstcount_master  : out std_logic_vector(4 downto 0);
    burstenable_master : out std_logic;

    read_data_avs    : in t_data;
    read_data_valid : in std_logic;

    waitrequest_avs : in std_logic;

    b_wr_cmd_empty : in std_logic;
    b_wr_cmd_rd_en : out std_logic;
    b_wr_cmd_data  : in std_logic_vector(61 downto 0);

    b_wr_data_empty : in std_logic;
    b_wr_data_rd_en : out std_logic;
    b_wr_data_data  : in std_logic_vector(63 downto 0);

    b_rd_cmd_full : in std_logic;
    b_rd_cmd_wr_en : out std_logic;
    b_rd_cmd_data  : out std_logic_vector(19 downto 0);

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
    x"FF",
	 x"0F", x"07", x"03", x"3F"
  );

  signal backend_paused : std_logic;
  
  signal nRST_internal : std_logic;

  signal s_read_op_req    : std_logic := '0;
  signal s_read_op_done   : std_logic := '0';
  
  signal s_cmd_op_id      : std_logic_vector(7 downto 0);
  signal s_cmd_datawidth  : std_logic_vector(11 downto 0);


begin

  nRST <= nRST_internal;

  process
    variable dummy_read : t_data := (others => '0');

    procedure bus_clear is
    begin
      read_master <= '0';
      write_master <= '0';
      address_master <= (others => '0');
      write_data_master <= (others => '0');
      byte_enable_master <= (others => '0');
      burstcount_master <= std_logic_vector(to_unsigned(1, burstcount_master'length)); 
      burstenable_master <= '0';
      wait until rising_edge(clk);
    end procedure;

    procedure test_pause(cycles : integer := 10) is
    begin
      for i in 1 to cycles loop
        wait until rising_edge(clk);
      end loop;
    end procedure;
    
  begin
    s_read_op_req <= '0';
    address_master <= (others => '0');
    read_master <= '0';
    write_master <= '0';
    byte_enable_master <= (others => '0');
    burstcount_master <= (others => '0');
    burstenable_master <= '0';
	 
	 nRST_internal <= '0';
	  for i in 1 to 2 loop
        wait until rising_edge(clk);
    end loop;
    nRST_internal <= '1';

    for i in 1 to 2 loop
        wait until rising_edge(clk);
    end loop;

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
        addr => std_logic_vector(to_unsigned(1 * 8, 25)),
        data => x"AAAA_BBBB_CCCC_DD" & TEST_BE_VECTORS(i),
        be => TEST_BE_VECTORS(i)
      );
		test_pause(10);
    end loop;
    

    nRST_internal <= '0';
    backend_paused <= '0';
    wait for 100 ns;
    nRST_internal <= '1';
    wait until rising_edge(clk);

    report "SCENARIO 2: Burst Writes (Burstcount=4)";
    for i in 15 to 17 loop
      address_master <= std_logic_vector(to_unsigned(1 * 64, 25));
      burstcount_master <= "00100";
      burstenable_master <= '1';
      write_master <= '1';
      byte_enable_master <= TEST_BE_VECTORS(i);
      write_data_master <= x"B1B1_B1B1_0000_00" & TEST_BE_VECTORS(i);

      wait until rising_edge(clk);
      burstenable_master <= '0';
      wait until rising_edge(clk) and waitrequest_avs = '0';
      for burst_step in 2 to 3 loop
			byte_enable_master <= x"FF";
        write_data_master <= std_logic_vector(to_unsigned(burst_step, 64));
        wait until rising_edge(clk) and waitrequest_avs = '0';
      end loop;
		
		byte_enable_master <= TEST_BE_VECTORS(i)(0) & TEST_BE_VECTORS(i)(1) & TEST_BE_VECTORS(i)(2)
									 & TEST_BE_VECTORS(i)(3) & TEST_BE_VECTORS(i)(4) & TEST_BE_VECTORS(i)(5)
									& TEST_BE_VECTORS(i)(6) & TEST_BE_VECTORS(i)(7);
      write_data_master <= std_logic_vector(to_unsigned(4, 64));
		wait until rising_edge(clk) and waitrequest_avs = '0';

      write_master <= '0';
      wait until rising_edge(clk);
      test_pause(10);
    end loop;
	 
	  test_pause(100);
	 
    bus_clear;

    
    nRST_internal <= '0';
    backend_paused <= '0';
    for i in 1 to 20 loop
        wait until rising_edge(clk);
    end loop;
    nRST_internal <= '1';
    wait until rising_edge(clk);
    
    report "SCENARIO 3: Burst Writes (Burstcount=16)";
    for i in 0 to 2 loop
      address_master <= std_logic_vector(to_unsigned(1 * 64, 25));
      burstcount_master <= "10000";
      burstenable_master <= '1';
      write_master <= '1';
      byte_enable_master <= TEST_BE_VECTORS(i);
      write_data_master <= x"B1B1_B1B1_0000_00" & TEST_BE_VECTORS(i);

      wait until rising_edge(clk);
      burstenable_master <= '0';
      wait until rising_edge(clk) and waitrequest_avs = '0';
      for burst_step in 2 to 15 loop
			byte_enable_master <= x"FF";
        write_data_master <= std_logic_vector(to_unsigned(burst_step, 64));
        wait until rising_edge(clk) and waitrequest_avs = '0';
      end loop;
		
		byte_enable_master <= TEST_BE_VECTORS(i)(0) & TEST_BE_VECTORS(i)(1) & TEST_BE_VECTORS(i)(2)
									 & TEST_BE_VECTORS(i)(3) & TEST_BE_VECTORS(i)(4) & TEST_BE_VECTORS(i)(5)
									& TEST_BE_VECTORS(i)(6) & TEST_BE_VECTORS(i)(7);
      write_data_master <= std_logic_vector(to_unsigned(4, 64));
		wait until rising_edge(clk) and waitrequest_avs = '0';

      write_master <= '0';
      wait until rising_edge(clk) and waitrequest_avs = '0';
      
      test_pause(10);
      
    end loop;
	 
	 test_pause(100);

	 
	 
    bus_clear;

    
    
    nRST_internal <= '0';
    backend_paused <= '0';
    for i in 1 to 20 loop
        wait until rising_edge(clk);
    end loop;
    nRST_internal <= '1';
    for i in 1 to 5 loop
        wait until rising_edge(clk);
    end loop;
    
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
        addr => std_logic_vector(to_unsigned(1 * 8, 25)),
        be => TEST_BE_VECTORS(i),
        data_out => dummy_read
      );
		 for i in 1 to 5 loop
			  wait until rising_edge(clk);
		 end loop;
    end loop;

    
    nRST_internal <= '0';
    backend_paused <= '0';
    for i in 1 to 20 loop
        wait until rising_edge(clk);
    end loop;
    nRST_internal <= '1';
    wait until rising_edge(clk);

    report "SCENARIO 5: Burst Reads (Burstcount=4)";
    for i in 0 to 2 loop
      wait until rising_edge(clk);
      wait until rising_edge(clk);
      address_master <= std_logic_vector(to_unsigned(1 * 64, 25));
      burstcount_master <= "00100";
      burstenable_master <= '1';
      read_master <= '1';
      byte_enable_master <= TEST_BE_VECTORS(i);
      wait until rising_edge(clk);
      burstenable_master <= '0';
      for i in 1 to 3 loop
        wait until rising_edge(clk);
      end loop;
      read_master <= '0';
      for burst_step in 2 to 16 loop
        wait until rising_edge(clk);
      end loop;
      for i in 1 to 128 loop
          wait until rising_edge(clk);
      end loop;
    end loop;
    
    nRST_internal <= '0';
    backend_paused <= '0';
    for i in 1 to 20 loop
        wait until rising_edge(clk);
    end loop;
    nRST_internal <= '1';
    wait until rising_edge(clk);
    
    
    report "SCENARIO 6: Burst Reads (Burstcount=16)";
    for i in 0 to 2 loop
      wait until rising_edge(clk);
      wait until rising_edge(clk);
      address_master <= std_logic_vector(to_unsigned(1 * 64, 25));
      burstcount_master <= "10000";
      burstenable_master <= '1';
      read_master <= '1';
      byte_enable_master <= TEST_BE_VECTORS(i);
      wait until rising_edge(clk);
      burstenable_master <= '0';
      for i in 1 to 3 loop
        wait until rising_edge(clk);
      end loop;
      read_master <= '0';
      for burst_step in 2 to 16 loop
        wait until rising_edge(clk);
      end loop;
      for i in 1 to 128 loop
          wait until rising_edge(clk);
      end loop;
    end loop;
  
    nRST_internal <= '0';
    backend_paused <= '0';
    for i in 1 to 20 loop
        wait until rising_edge(clk);
    end loop;
    nRST_internal <= '1';
    wait until rising_edge(clk);
  

    report "SCENARIO 7: FIFO overload";
    backend_paused <= '1';
    for i in 1 to 255 loop
        avalon_single_write(
            clk => clk,
            waitrequest => waitrequest_avs,
            address => address_master,
            write => write_master,
            read => read_master,
            writedata => write_data_master,
            byteenable => byte_enable_master,
            addr => std_logic_vector(to_unsigned(1 * 64, 25)),
            data => x"DEAD_BEEF_F00D_CAFE",
            be => x"FF"
        );
      
    end loop;
    
    report "END OF SCENARIO 7 overload attempts";
    backend_paused <= '0';
    for i in 1 to 200 loop
        wait until rising_edge(clk);
    end loop;

    backend_paused <= '0';
    for i in 1 to 20 loop
        wait until rising_edge(clk);
    end loop;
    
    nRST_internal <= '0';
    backend_paused <= '0';
    for i in 1 to 20 loop
        wait until rising_edge(clk);
    end loop;
    nRST_internal <= '1';
    wait until rising_edge(clk);
    

    report "SCENARIO 8: Burst Writes with mid-burst break";
    for i in 0 to 1 loop
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        
        address_master <= std_logic_vector(to_unsigned(1 * 128, 25));
        burstcount_master <= "01000";
        burstenable_master <= '1';
        write_master <= '1';
        byte_enable_master <= x"FF";
        write_data_master <= x"1111_1111_1111_1111";
        
        wait until rising_edge(clk);
        burstenable_master <= '0';
        
        for burst_step in 1 to 2 loop
            write_data_master <= std_logic_vector(to_unsigned(burst_step, 64));
            wait until rising_edge(clk) and waitrequest_avs = '0';
        end loop;
        

        write_master <= '0';
        report "Burst write break point - write signal deasserted";
        
        for break_cycle in 1 to 3 loop
            wait until rising_edge(clk);
        end loop;
        
        write_master <= '1';
        report "Burst write resumed - write signal reasserted";
        
        for burst_step in 3 to 7 loop
            write_data_master <= std_logic_vector(to_unsigned(burst_step, 64));
            wait until rising_edge(clk) and waitrequest_avs = '0';
        end loop;
        
        write_data_master <= x"FFFF_FFFF_FFFF_FFFF";
        wait until rising_edge(clk) and waitrequest_avs = '0';
        
        write_master <= '0';
        wait until rising_edge(clk);
        
        test_pause(20);
    end loop;
    bus_clear;
    
    
    nRST_internal <= '0';
    backend_paused <= '0';
    for i in 1 to 20 loop
        wait until rising_edge(clk);
    end loop;
    nRST_internal <= '1';
    wait until rising_edge(clk);
    
    report "SCENARIO 9: Burst reads with sustained read signal";
    report "Starting burst read chain with read signal kept high...";

    report "Step 1: First burst (burstcount=4)";
    address_master <= std_logic_vector(to_unsigned(1 * 64, 25));
    burstcount_master <= "00100";
    burstenable_master <= '1';
    read_master <= '1';
    byte_enable_master <= x"FF";
    wait until rising_edge(clk);
    burstenable_master <= '0'; 
    wait until rising_edge(clk) and waitrequest_avs = '0';
    report "First burst accepted, waitrequest = 0";
    
    report "Step 2: Second burst (burstcount=8) with read still high";
    address_master <= std_logic_vector(to_unsigned(1 * 64, 25));
    burstcount_master <= "00010";
    burstenable_master <= '1';
    wait until rising_edge(clk);
    burstenable_master <= '0'; 
    wait until rising_edge(clk) and waitrequest_avs = '0';
    report "Second burst accepted, waitrequest = 0";
    

    report "Step 3: Single read with read still high";
    address_master <= std_logic_vector(to_unsigned(1 * 8, 25));
    burstcount_master <= "00001";
    burstenable_master <= '0';
    

    wait until rising_edge(clk) and waitrequest_avs = '0';
    report "Single read accepted, waitrequest = 0";
    
    burstcount_master <= "00001";

    report "Step 4: Lowering read signal based on waitrequest";
    
    wait until rising_edge(clk);
    read_master <= '0';
    
    bus_clear;
    
    for i in 1 to 100 loop
        wait until rising_edge(clk);
    end loop;
    nRST_internal <= '0';
    backend_paused <= '0';
    for i in 1 to 20 loop
        wait until rising_edge(clk);
    end loop;
    nRST_internal <= '1';
    wait until rising_edge(clk);
    
    
    report "--- ALL TEST SCENARIOS COMPLETED ---" severity failure;

  end process;

  process(clk)
    variable v_cmd_data : std_logic_vector(61 downto 0);
    type t_state is (IDLE, READ_CMD, DECODE, WAIT_READ_DONE, DRAIN_WR_DATA );
    variable v_state : t_state := IDLE;
    
    variable v_op_write : std_logic;
    variable v_cmd_width_bytes : unsigned(11 downto 0);
    variable v_words_to_drain : integer;
  begin
    if rising_edge(clk) then
      if nRST_internal = '0' then
        b_wr_cmd_rd_en <= '0';
        b_wr_data_rd_en <= '0';
        s_cmd_op_id <= (others => '0');
        s_cmd_datawidth <= (others => '0');
		  s_read_op_req <= '0';
        v_state := IDLE;
      else
        case v_state is
          when IDLE =>

            if b_wr_cmd_empty = '0' then
              b_wr_cmd_rd_en <= '1';
              v_state := READ_CMD;
            else
              b_wr_cmd_rd_en <= '0';
            end if;
            
          when READ_CMD =>
            b_wr_cmd_rd_en <= '0';
            v_cmd_data := b_wr_cmd_data;
            v_state := DECODE;
            
          when DECODE =>
            v_op_write := v_cmd_data(61);
            v_cmd_width_bytes := unsigned(v_cmd_data(35 downto 24));	
            if v_op_write = '1' then
              v_words_to_drain := (to_integer(v_cmd_width_bytes) + 7) / 8;
              if v_words_to_drain > 0 then
                 v_state := DRAIN_WR_DATA;
              else
                 v_state := IDLE;
              end if;
            else
						report "pip";
						s_cmd_op_id <= v_cmd_data(7 downto 0);
						s_cmd_datawidth <= v_cmd_data(35 downto 24);
                 s_read_op_req <= '1';
					  report "Read operation requested, op_id: " & integer'image(to_integer(unsigned(v_cmd_data(7 downto 0))));
					  v_state := WAIT_READ_DONE;
            end if;

          when DRAIN_WR_DATA =>
				   report "DRAIN"& integer'image(v_words_to_drain);
              if b_wr_data_empty = '0' and backend_paused = '0' then
                  b_wr_data_rd_en <= '1';
                  v_words_to_drain := v_words_to_drain - 1;
              else
						if v_words_to_drain <= 0 then
							b_wr_data_rd_en <= '0';
							v_state := IDLE;
						end if;
                  b_wr_data_rd_en <= '0';
						
              end if;
			
          when WAIT_READ_DONE =>
            if s_read_op_done = '1' then
					report "lol";
              s_read_op_req <= '0';
              v_state := IDLE;
            end if;
        end case;
      end if;
    end if;
  end process;
  

  process(clk)

    type t_rd_state is (IDLE, CALC_SIZE, GEN_DATA, WAIT_DELAY, SEND_CMD, WAIT_REQ_LOW);
    variable v_rd_state : t_rd_state := IDLE;
    variable v_words_count : integer;
    variable v_words_sent : integer;
    

    variable v_delay_cnt : integer range 0 to 20 := 0;
  begin
    if rising_edge(clk) then
      if nRST_internal = '0' then
        b_rd_cmd_wr_en <= '0';
        b_rd_data_wr_en <= '0';
        b_rd_data_data <= (others => '0');
        s_read_op_done <= '0';
        v_rd_state := IDLE;
        v_delay_cnt := 0;
      else
        case v_rd_state is
          when IDLE =>
            if s_read_op_req = '1' then 
				report "pop";
               v_rd_state := CALC_SIZE;
            end if;
            
          when CALC_SIZE =>
            v_words_count := (to_integer(unsigned(s_cmd_datawidth)) + 7) / 8;
            if v_words_count = 0 then 
					v_rd_state := IDLE;
					s_read_op_done <= '1';
					s_read_op_req <= '0';
				else 
            v_words_sent := 1;
            v_rd_state := GEN_DATA;
				end if;
            
          when GEN_DATA =>
					report "GENA";
            if v_words_sent < v_words_count + 1 then
              if b_rd_data_full = '0' then
					report "pop";
                b_rd_data_wr_en <= '1';
                b_rd_data_data <= x"00000000" & std_logic_vector(to_unsigned(v_words_sent, 32));
                v_words_sent := v_words_sent + 1;
              else
                b_rd_data_wr_en <= '0'; 
              end if;
            else
              b_rd_data_wr_en <= '0';
              

              v_delay_cnt := 0;
              v_rd_state := WAIT_DELAY; 
            end if;


          when WAIT_DELAY =>
             if v_delay_cnt < 10 then
                v_delay_cnt := v_delay_cnt + 1;
             else
                v_rd_state := SEND_CMD;
             end if;
            
          when SEND_CMD =>

             if b_rd_cmd_full = '0' then
                b_rd_cmd_wr_en <= '1';

                b_rd_cmd_data <= std_logic_vector(s_cmd_datawidth) & std_logic_vector(s_cmd_op_id);
               
                s_read_op_done <= '1';
                v_rd_state := WAIT_REQ_LOW;
             else
                b_rd_cmd_wr_en <= '0';
             end if;
             
          when WAIT_REQ_LOW =>
             b_rd_cmd_wr_en <= '0';

             if s_read_op_req = '0' then
                s_read_op_done <= '0';
                v_rd_state := IDLE; 
             end if;
             
        end case;
      end if;
    end if;
  end process;

end architecture;
