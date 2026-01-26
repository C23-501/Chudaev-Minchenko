library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package AvalonMM_SlavePackage is

  subtype t_addr is std_logic_vector(24 downto 0);
  subtype t_data is std_logic_vector(63 downto 0);
  subtype t_be   is std_logic_vector(7 downto 0);
  subtype t_bc   is std_logic_vector(4 downto 0);

  procedure avalon_single_write (
    signal clk         : in  std_logic;
    signal waitrequest : in  std_logic;
    signal address     : out t_addr;
    signal write       : out std_logic;
    signal read        : out std_logic;
    signal writedata   : out t_data;
    signal byteenable  : out t_be;
    constant addr      : in  t_addr;
    constant data      : in  t_data;
    constant be        : in  t_be
  );

  procedure avalon_single_read (
    signal clk         : in  std_logic;
    signal waitrequest : in  std_logic;
    signal readdata    : in  t_data;
    signal address     : out t_addr;
    signal read        : out std_logic;
    signal write       : out std_logic;
    signal byteenable  : out t_be;
    constant addr      : in  t_addr;
    constant be        : in  t_be;
    variable data_out  : out t_data
  );

  procedure avalon_burst_write (
    signal clk         : in  std_logic;
    signal waitrequest : in  std_logic;
    signal address     : out t_addr;
    signal write       : out std_logic;
    signal read        : out std_logic;
    signal writedata   : out t_data;
    signal byteenable  : out t_be;
    signal burstcount  : out t_bc;
    signal burstenable : out std_logic;
    constant start_addr: in  t_addr;
    constant count     : in  integer;
    constant data      : in  t_data;
    constant be        : in  t_be
  );

end package;

package body AvalonMM_SlavePackage is

  -- --- SINGLE WRITE ---
  procedure avalon_single_write (
    signal clk         : in  std_logic;
    signal waitrequest : in  std_logic;
    signal address     : out t_addr;
    signal write       : out std_logic;
    signal read        : out std_logic;
    signal writedata   : out t_data;
    signal byteenable  : out t_be;
    constant addr      : in  t_addr;
    constant data      : in  t_data;
    constant be        : in  t_be
  ) is
  begin
    read       <= '0';
    address    <= addr;
    writedata  <= data;
    byteenable <= be;
    write      <= '1';

	 wait until rising_edge(clk);
	 wait until rising_edge(clk);
	 wait until rising_edge(clk);
	 
    loop
      wait until rising_edge(clk);
      exit when waitrequest = '0';
    end loop;
	 
    write <= '0';
  end procedure;

  procedure avalon_single_read (
    signal clk         : in  std_logic;
    signal waitrequest : in  std_logic;
    signal readdata    : in  t_data;
    signal address     : out t_addr;
    signal read        : out std_logic;
    signal write       : out std_logic;
    signal byteenable  : out t_be;
    constant addr      : in  t_addr;
    constant be        : in  t_be;
    variable data_out  : out t_data
  ) is
  begin
    write      <= '0';
    address    <= addr;
    byteenable <= be;
    read       <= '1';

	 wait until rising_edge(clk);

	 
    loop
      wait until rising_edge(clk);
      exit when waitrequest = '0';
    end loop;
    read     <= '0';
    data_out := readdata;
    
  end procedure;

	procedure avalon_burst_write (
	  signal clk         : in  std_logic;
	  signal waitrequest : in  std_logic;
	  signal address     : out t_addr;
	  signal write       : out std_logic;
	  signal read        : out std_logic;
	  signal writedata   : out t_data;
	  signal byteenable  : out t_be;
	  signal burstcount  : out t_bc;
	  signal burstenable : out std_logic;
	  constant start_addr: in  t_addr;
	  constant count     : in  integer;
	  constant data      : in  t_data;
	  constant be        : in  t_be
	) is
	begin
	  read        <= '0';
	  address     <= start_addr;
	  burstcount  <= std_logic_vector(to_unsigned(count, 5));
	  burstenable <= '1';
	  byteenable  <= be;
	  writedata   <= data;  -- Первые данные уже здесь
	  write       <= '1';

	  -- Ждем, пока slave будет готов принять первую транзакцию
	  loop
		 wait until rising_edge(clk);
		 exit when waitrequest = '0';
	  end loop;

	  burstenable <= '0';
	  
	  -- Отправляем оставшиеся count-1 данных
	  for i in 2 to count loop
		 writedata <= data;

		 loop
			wait until rising_edge(clk);
			exit when waitrequest = '0';
		 end loop;
	  end loop;

	  write <= '0';
	end procedure;

end package body;