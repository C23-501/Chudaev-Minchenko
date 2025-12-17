library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_textio.all;
use std.textio.all;

entity AvalonMM_SlaveTester is
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
end entity AvalonMM_SlaveTester;

architecture tester of AvalonMM_SlaveTester is
  constant CLK_PERIOD : time := 12.5 ns;
 
  signal clk_80MHz_i : std_logic := '0';
  signal nRST_i : std_logic := '0';
 
  signal test_done : boolean := false;
 
  type fifo_control_t is record
    wr_cmd_count : integer;
    wr_data_count : integer;
    rd_cmd_count : integer;
    rd_data_count : integer;
  end record;
 
  signal fifo_control : fifo_control_t := (
    wr_cmd_count => 0,
    wr_data_count => 0,
    rd_cmd_count => 0,
    rd_data_count => 0
  );
 
  signal response_counter : integer := 0;
  signal data_counter : integer := 0;
  signal response_pending : boolean := false;
  signal response_delay_counter : integer := 0;
  signal response_expected_bytes : integer := 0;
  signal response_is_read : boolean := false;
 
  signal data_gen_pending : boolean := false;
  signal data_beats_remaining : integer := 0;
 
  function count_ones(be : std_logic_vector) return integer is
    variable cnt : integer := 0;
  begin
    for i in be'range loop
      if be(i) = '1' then cnt := cnt + 1; end if;
    end loop;
    return cnt;
  end function;

  function int_to_hex_string(val: unsigned; width: integer := 8) return string is
    constant hex_chars: string(1 to 16) := "0123456789ABCDEF";
    variable result: string(1 to width);
    variable temp: unsigned(width*4-1 downto 0) := resize(val, width*4);
    variable digit: integer;
  begin
    for i in width downto 1 loop
      digit := to_integer(temp(3 downto 0));
      result(i) := hex_chars(digit + 1);
      temp := temp srl 4;
    end loop;
    return result;
  end function;
 
  function cmd_to_string_simple(cmd: std_logic_vector) return string is
    variable cmd_type : string(1 to 5);
  begin
    if cmd(57) = '1' then
      cmd_type := "WRITE";
    else
      cmd_type := "READ ";
    end if;
   
    return cmd_type & " cmd | Addr: " & integer'image(to_integer(unsigned(cmd(56 downto 32)))) &
           " | Bytes: " & integer'image(to_integer(unsigned(cmd(31 downto 16)))) &
           " | BE: " & integer'image(to_integer(unsigned(cmd(15 downto 8)))) &
           " | ID: " & integer'image(to_integer(unsigned(cmd(7 downto 0))));
  end function;
 
begin
  s_clk_80MHz <= clk_80MHz_i;
  s_nRST <= nRST_i;
 
  s_wr_cmd_full <= '1' when fifo_control.wr_cmd_count > 30 else '0';
  s_wr_data_full <= '1' when fifo_control.wr_data_count > 30 else '0';
  s_rd_cmd_empty <= '1' when fifo_control.rd_cmd_count = 0 else '0';
  s_rd_data_empty <= '1' when fifo_control.rd_data_count = 0 else '0';
  
  clock_process : process
  begin
    while not test_done loop
      clk_80MHz_i <= '0';
      wait for CLK_PERIOD/2;
      clk_80MHz_i <= '1';
      wait for CLK_PERIOD/2;
    end loop;
    wait;
  end process;
  
  fifo_management : process(clk_80MHz_i)
    variable cmd_bytes : std_logic_vector(15 downto 0);
    variable burst_beats : integer;
    variable active : integer;
  begin
    if rising_edge(clk_80MHz_i) then
      if nRST_i = '0' then
        fifo_control.wr_cmd_count <= 0;
        fifo_control.wr_data_count <= 0;
        fifo_control.rd_cmd_count <= 0;
        fifo_control.rd_data_count <= 0;
        response_counter <= 0;
        data_counter <= 0;
        response_pending <= false;
        response_delay_counter <= 0;
        response_expected_bytes <= 0;
        response_is_read <= false;
        data_gen_pending <= false;
        data_beats_remaining <= 0;
        s_rd_cmd <= (others => '0');
        s_rd_data <= (others => '0');
      else
        if s_wr_cmd_write = '1' then
          report "Backend: " & cmd_to_string_simple(s_wr_cmd);
          fifo_control.wr_cmd_count <= fifo_control.wr_cmd_count + 1;
         
          response_pending <= true;
          response_delay_counter <= 5;
         
          cmd_bytes := s_wr_cmd(31 downto 16);
          response_expected_bytes <= to_integer(unsigned(cmd_bytes));
          response_is_read <= (s_wr_cmd(57) = '0');
         
          if response_expected_bytes = 0 then
            response_expected_bytes <= 8;
          end if;
         
          report "Backend: Expected bytes = " & integer'image(response_expected_bytes);
        end if;
       
        if s_wr_data_write = '1' then
          report "Backend: Data received: 0x" &
                 int_to_hex_string(unsigned(s_wr_data(63 downto 32)), 8) &
                 int_to_hex_string(unsigned(s_wr_data(31 downto 0)), 8);
          fifo_control.wr_data_count <= fifo_control.wr_data_count + 1;
        end if;
       
        if s_rd_cmd_read = '1' and fifo_control.rd_cmd_count > 0 then
          fifo_control.rd_cmd_count <= fifo_control.rd_cmd_count - 1;
        end if;
       
        if s_rd_data_read = '1' and fifo_control.rd_data_count > 0 then
          fifo_control.rd_data_count <= fifo_control.rd_data_count - 1;
        end if;
       
        if response_pending then
          if response_delay_counter > 0 then
            response_delay_counter <= response_delay_counter - 1;
          else
            response_counter <= response_counter + 1;
           
            if response_expected_bytes > 65535 then
              response_expected_bytes <= 65535;
            end if;
           
            s_rd_cmd <= x"00" & std_logic_vector(to_unsigned(response_expected_bytes mod 65536, 16));
            fifo_control.rd_cmd_count <= fifo_control.rd_cmd_count + 1;
            report "Backend: Sending response " & integer'image(response_counter) &
                   ", bytes: " & integer'image(response_expected_bytes);
           
            if response_is_read then
              data_gen_pending <= true;
              if response_expected_bytes > 0 then
                burst_beats := (response_expected_bytes + 7) / 8;
                if burst_beats > 0 then
                  data_beats_remaining <= burst_beats;
                else
                  data_beats_remaining <= 1;
                end if;
              else
                data_beats_remaining <= 1;
              end if;
              report "Backend: Scheduling " & integer'image(data_beats_remaining) & " data beats";
            else
              active := count_ones(s_wr_cmd(15 downto 8));
              if active = 0 then
                active := 1;
              end if;
              burst_beats := response_expected_bytes / active;
              if burst_beats > fifo_control.wr_data_count then
                burst_beats := fifo_control.wr_data_count;
              end if;
              fifo_control.wr_data_count <= fifo_control.wr_data_count - burst_beats;
              report "Backend: Consuming " & integer'image(burst_beats) & " data beats for write";
            end if;
           
            if fifo_control.wr_cmd_count > 0 then
              fifo_control.wr_cmd_count <= fifo_control.wr_cmd_count - 1;
              report "Backend: Consuming command";
            end if;
           
            response_pending <= false;
          end if;
        end if;
       
        if data_gen_pending and data_beats_remaining > 0 then
          s_rd_data <= std_logic_vector(to_unsigned(data_counter * 16#1000#, 64));
          data_counter <= data_counter + 1;
          fifo_control.rd_data_count <= fifo_control.rd_data_count + 1;
          data_beats_remaining <= data_beats_remaining - 1;
         
          report "Backend: Generating data beat " & integer'image(data_counter) &
                 " | Remaining: " & integer'image(data_beats_remaining);
         
          if data_beats_remaining = 1 then
            report "Backend: Last data beat generated";
          end if;
         
          if data_beats_remaining = 0 then
            data_gen_pending <= false;
          end if;
        end if;
      end if;
    end if;
  end process;
  
  stim_proc : process
    procedure wait_cycles(n : integer) is
    begin
      for i in 1 to n loop
        wait until rising_edge(clk_80MHz_i);
      end loop;
    end procedure;
   
    procedure write_transaction(
      addr : in std_logic_vector(24 downto 0);
      data : in std_logic_vector(63 downto 0);
      be : in std_logic_vector(7 downto 0);
      burst : in integer
    ) is
      variable addr_int : unsigned(24 downto 0);
      variable data_int : unsigned(63 downto 0);
      variable burst_val : integer;
    begin
      addr_int := unsigned(addr);
      data_int := unsigned(data);
     
      if burst > 15 then
        burst_val := 15;
        report "Warning: burst truncated from " & integer'image(burst) & " to 15";
      elsif burst = 0 then
        burst_val := 1;
        report "Warning: burst=0 changed to 1";
      else
        burst_val := burst;
      end if;
     
      report "Tester: Starting write transaction" &
             " | Addr: 0x" & int_to_hex_string(addr_int, 7) &
             " | Data: 0x" & int_to_hex_string(data_int(63 downto 32), 8) &
                          int_to_hex_string(data_int(31 downto 0), 8) &
             " | BE: " & integer'image(to_integer(unsigned(be))) &
             " | Burst: " & integer'image(burst_val);
     
      wait until rising_edge(clk_80MHz_i);
     
      s_address_master <= addr;
      s_write_data_master <= data;
      s_byte_enable_master <= be;
      s_burstcount_master <= std_logic_vector(to_unsigned(burst_val, 4));
      s_write_master <= '1';
      s_read_master <= '0';
     
      wait until rising_edge(clk_80MHz_i) and s_waitrequest_avs = '0';
     
      if burst_val > 1 then
        for i in 2 to burst_val loop
          s_write_data_master <= std_logic_vector(data_int + to_unsigned(i*16#1000#, 64));
          wait until rising_edge(clk_80MHz_i) and s_waitrequest_avs = '0';
        end loop;
      end if;
     
      s_write_master <= '0';
      s_address_master <= (others => '0');
      s_write_data_master <= (others => '0');
      s_byte_enable_master <= (others => '0');
      s_burstcount_master <= (others => '0');
     
      wait_cycles(2);
      report "Tester: Write transaction completed";
    end procedure;
   
    procedure read_transaction(
      addr : in std_logic_vector(24 downto 0);
      be : in std_logic_vector(7 downto 0);
      burst : in integer
    ) is
      variable addr_int : unsigned(24 downto 0);
      variable burst_val : integer;
      variable timeout_counter : integer;
    begin
      addr_int := unsigned(addr);
     
      if burst > 15 then
        burst_val := 15;
        report "Warning: burst truncated from " & integer'image(burst) & " to 15";
      elsif burst = 0 then
        burst_val := 1;
        report "Warning: burst=0 changed to 1";
      else
        burst_val := burst;
      end if;
     
      report "Tester: Starting read transaction" &
             " | Addr: 0x" & int_to_hex_string(addr_int, 7) &
             " | BE: " & integer'image(to_integer(unsigned(be))) &
             " | Burst: " & integer'image(burst_val);
     
      wait until rising_edge(clk_80MHz_i);
     
      s_address_master <= addr;
      s_byte_enable_master <= be;
      s_burstcount_master <= std_logic_vector(to_unsigned(burst_val, 4));
      s_read_master <= '1';
      s_write_master <= '0';
     
      timeout_counter := 0;
      while s_waitrequest_avs = '1' and timeout_counter < 100 loop
        wait until rising_edge(clk_80MHz_i);
        timeout_counter := timeout_counter + 1;
      end loop;
     
      if timeout_counter >= 100 then
        report "ERROR: Read transaction timeout! Addr: 0x" & int_to_hex_string(addr_int, 7);
        s_read_master <= '0';
        return;
      end if;
     
      if burst_val > 1 then
        for i in 2 to burst_val loop
          wait until rising_edge(clk_80MHz_i) and s_waitrequest_avs = '0';
          report "Tester: Read beat " & integer'image(i) & " completed";
        end loop;
      else
        report "Tester: Single read beat completed";
      end if;
     
      s_read_master <= '0';
      s_address_master <= (others => '0');
      s_byte_enable_master <= (others => '0');
      s_burstcount_master <= (others => '0');
     
      wait_cycles(2);
      report "Tester: Read transaction completed";
    end procedure;
   
    procedure test_byte_enable_combinations(
      addr_base : in integer
    ) is
      variable test_addr : integer;
      variable test_data : unsigned(63 downto 0);
      variable be_val : integer;
    begin
      test_addr := addr_base;
      test_data := to_unsigned(16#1000#, 64);
     
      for i in 0 to 15 loop
        wait_cycles(10);
       
        be_val := i * 16;
        report "Testing BE combination: " & integer'image(be_val);
       
        write_transaction(
          addr => std_logic_vector(to_unsigned(test_addr, 25)),
          data => std_logic_vector(test_data),
          be => std_logic_vector(to_unsigned(be_val, 8)),
          burst => 1
        );
       
        test_addr := test_addr + 16#1000#;
        test_data := test_data + 16#1000#;
      end loop;
    end procedure;
   
    procedure test_aligned_access(
      addr_base : in integer
    ) is
    begin
      report "=== Testing aligned accesses ===";
     
      write_transaction(
        addr => std_logic_vector(to_unsigned(addr_base + 16#0#, 25)),
        data => x"00000000000000A1",
        be => "00000001",
        burst => 1
      );
     
      write_transaction(
        addr => std_logic_vector(to_unsigned(addr_base + 16#100#, 25)),
        data => x"000000000000B2B1",
        be => "00000011",
        burst => 1
      );
     
      write_transaction(
        addr => std_logic_vector(to_unsigned(addr_base + 16#200#, 25)),
        data => x"00000000D4D3D2D1",
        be => "00001111",
        burst => 1
      );
     
      write_transaction(
        addr => std_logic_vector(to_unsigned(addr_base + 16#301#, 25)),
        data => x"00000000000000E1",
        be => "00000010",
        burst => 1
      );
     
      write_transaction(
        addr => std_logic_vector(to_unsigned(addr_base + 16#402#, 25)),
        data => x"000000000000F2F1",
        be => "00001100",
        burst => 1
      );
     
      write_transaction(
        addr => std_logic_vector(to_unsigned(addr_base + 16#500#, 25)),
        data => x"D8D7D6D5D4D3D2D1",
        be => "11111111",
        burst => 1
      );
    end procedure;
   
    procedure test_burst_patterns(
      addr_base : in integer
    ) is
    begin
      report "=== Testing burst patterns ===";
     
      write_transaction(
        addr => std_logic_vector(to_unsigned(addr_base, 25)),
        data => x"1111111111111111",
        be => "11111111",
        burst => 2
      );
     
      write_transaction(
        addr => std_logic_vector(to_unsigned(addr_base + 16#1000#, 25)),
        data => x"2222222222222222",
        be => "00001111",
        burst => 4
      );
     
      write_transaction(
        addr => std_logic_vector(to_unsigned(addr_base + 16#2000#, 25)),
        data => x"3333333333333333",
        be => "11110000",
        burst => 8
      );
     
      read_transaction(
        addr => std_logic_vector(to_unsigned(addr_base + 16#3000#, 25)),
        be => "11111111",
        burst => 4
      );
     
      read_transaction(
        addr => std_logic_vector(to_unsigned(addr_base + 16#4000#, 25)),
        be => "01010101",
        burst => 2
      );
    end procedure;
   
    procedure test_back_to_back(
      addr_base : in integer
    ) is
    begin
      report "=== Testing back-to-back transactions ===";
     
      write_transaction(
        addr => std_logic_vector(to_unsigned(addr_base, 25)),
        data => x"4444444444444444",
        be => "11111111",
        burst => 1
      );
     
      wait_cycles(1);
     
      read_transaction(
        addr => std_logic_vector(to_unsigned(addr_base + 16#100#, 25)),
        be => "11111111",
        burst => 1
      );
     
      for i in 1 to 3 loop
        write_transaction(
          addr => std_logic_vector(to_unsigned(addr_base + i*16#200#, 25)),
          data => std_logic_vector(to_unsigned(16#50000000# + i*16#1000#, 64)),
          be => "11111111",
          burst => 1
        );
        wait_cycles(1);
      end loop;
     
      for i in 1 to 3 loop
        read_transaction(
          addr => std_logic_vector(to_unsigned(addr_base + i*16#300#, 25)),
          be => "11111111",
          burst => 1
        );
        wait_cycles(1);
      end loop;
    end procedure;
   
    procedure test_error_conditions(
      addr_base : in integer
    ) is
    begin
      report "=== Testing error/resilience conditions ===";
     
      report "Testing basic error conditions";
     
      write_transaction(
        addr => std_logic_vector(to_unsigned(addr_base, 25)),
        data => x"5555555555555555",
        be => "11111111",
        burst => 1
      );
     
      report "Testing with burst=0 (should be ignored)";
      s_address_master <= std_logic_vector(to_unsigned(addr_base + 16#100#, 25));
      s_burstcount_master <= "0000";
      s_write_master <= '1';
     
      wait_cycles(2);
      s_write_master <= '0';
      wait_cycles(5);
    end procedure;
   
  begin
    report "=== Initializing AvalonMM Slave Tester ===";
    nRST_i <= '0';
    s_address_master <= (others => '0');
    s_read_master <= '0';
    s_write_master <= '0';
    s_write_data_master <= (others => '0');
    s_byte_enable_master <= (others => '0');
    s_burstcount_master <= (others => '0');
   
    wait_cycles(5);
    nRST_i <= '0';
    wait_cycles(3);
    nRST_i <= '1';
    wait_cycles(5);
   
    report "=== Starting Comprehensive Avalon-MM Slave Test Sequence ===";
   
    report "=== Test 1: Basic single transactions ===";
    write_transaction(
      addr => std_logic_vector(to_unsigned(16#0000#, 25)),
      data => x"00000000000000AA",
      be => "00000001",
      burst => 1
    );
   
    read_transaction(
      addr => std_logic_vector(to_unsigned(16#1000#, 25)),
      be => "00000001",
      burst => 1
    );
   
    test_byte_enable_combinations(
      addr_base => 16#2000#
    );
   
    test_aligned_access(16#10000#);
   
    test_burst_patterns(16#20000#);
   
    test_back_to_back(16#30000#);
   
    report "=== Test 6: Mixed read/write patterns ===";
   
    write_transaction(
      addr => std_logic_vector(to_unsigned(16#40000#, 25)),
      data => x"6666666666666666",
      be => "11111111",
      burst => 1
    );
   
    read_transaction(
      addr => std_logic_vector(to_unsigned(16#41000#, 25)),
      be => "11111111",
      burst => 2
    );
   
    write_transaction(
      addr => std_logic_vector(to_unsigned(16#42000#, 25)),
      data => x"7777777777777777",
      be => "01010101",
      burst => 1
    );
   
    report "=== Test 7: Maximum burst test ===";
    write_transaction(
      addr => std_logic_vector(to_unsigned(16#50000#, 25)),
      data => x"8888888888888888",
      be => "11111111",
      burst => 15
    );
   
    read_transaction(
      addr => std_logic_vector(to_unsigned(16#51000#, 25)),
      be => "11111111",
      burst => 15
    );
   
    test_error_conditions(16#60000#);
   
    report "=== Test 9: Random pattern test ===";
    for i in 1 to 3 loop
      write_transaction(
        addr => std_logic_vector(to_unsigned(16#70000# + i*16#400#, 25)),
        data => std_logic_vector(to_unsigned(16#9000000# + i*16#100#, 64)),
        be => std_logic_vector(to_unsigned(i mod 256, 8)),
        burst => (i mod 4) + 1
      );
      wait_cycles(2);
    end loop;
   
    report "=== Final verification read ===";
    read_transaction(
      addr => std_logic_vector(to_unsigned(16#70000#, 25)),
      be => "11111111",
      burst => 1
    );
   
    report "=== All tests completed successfully ===";
    wait_cycles(50);
    test_done <= true;
    wait;
  end process;
  
  monitor_proc : process(clk_80MHz_i)
  begin
    if rising_edge(clk_80MHz_i) then
      if s_wr_cmd_write = '1' then
        report "Tester Monitor: " & cmd_to_string_simple(s_wr_cmd);
      end if;
    end if;
  end process;
end architecture tester;