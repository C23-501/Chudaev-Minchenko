library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

entity AvalonMM_Slave is
port (
    clk_80MHz : in std_logic;
    nRST : in std_logic;
    address_master : in std_logic_vector(24 downto 0);
    read_master : in std_logic;
    write_master : in std_logic;
    write_data_master : in std_logic_vector(63 downto 0);
    byte_enable_master : in std_logic_vector(7 downto 0);
    burstcount_master : in std_logic_vector(4 downto 0);
    burstenable_master : in std_logic;
    read_data_avs : out std_logic_vector(63 downto 0);
    waitrequest_avs : out std_logic;
    read_data_valid : out std_logic;
    wr_cmd_full : in std_logic;
    wr_cmd : out std_logic_vector(61 downto 0);
    wr_cmd_write : out std_logic;
    wr_data_full : in std_logic;
    wr_data_used : in std_logic_vector(9 downto 0); 
    wr_data : out std_logic_vector(63 downto 0);
    wr_data_write : out std_logic;
    rd_cmd_empty : in std_logic;
    rd_cmd : in std_logic_vector(19 downto 0);
    rd_cmd_read : out std_logic;
    rd_data_empty : in std_logic;
    rd_data : in std_logic_vector(63 downto 0);
    rd_data_read : out std_logic;
    led_control : out STD_LOGIC_VECTOR (7 downto 0)
);
end entity AvalonMM_Slave;

architecture rtl of AvalonMM_Slave is
    type master_state_t is (
        IDLE, SINGLE_READ, PREPARE_HEADER, WRITE_HEADER,
        WAIT_READ_DATA, SEND_READ_DATA,
        SINGLE_WRITE, WRITE_DATA, BURST_READ, BURST_WRITE, BURST_WRITE_DATA
    );
    type internal_state_t is (
        IDLE, READ_HEADER, PREPARE_ANSWER, READ_DATA
    );
    
    constant WR_DATA_FIFO_DEPTH : integer := 512;
    signal master_state : master_state_t;
    signal internal_state : internal_state_t;
    signal captured_addr_avalon_r : std_logic_vector(24 downto 0);
    signal captured_be_avalon_r : std_logic_vector(7 downto 0);
    signal captured_be_last_r : std_logic_vector(7 downto 0);
    signal avs_read_r : std_logic;
    signal avs_write_r : std_logic;
    signal avs_burstenable_r : std_logic;
    signal burstcount_r : std_logic_vector(4 downto 0);
    signal op_id_cnt : std_logic_vector(7 downto 0);
    signal current_resp_id : std_logic_vector(7 downto 0);
    signal current_data_width : std_logic_vector(11 downto 0);
    signal read_data_r : std_logic_vector(63 downto 0);
    signal data_width_r : std_logic_vector(11 downto 0);
    signal wr_cmd_write_r : std_logic;
    signal wr_data_write_r : std_logic;
    signal rd_cmd_read_r : std_logic;
    signal rd_data_read_r : std_logic;
    signal burst_rd_done : std_logic;
    signal waitrequest_r : std_logic;
    signal burst_write_words_sent : std_logic_vector(4 downto 0);
    signal exec_cmd_r : std_logic_vector(61 downto 0);
    signal burst_queue : std_logic_vector(63 downto 0);
    signal q_wr_ptr : std_logic_vector(3 downto 0); 
    signal q_rd_ptr : std_logic_vector(3 downto 0); 
    signal trans_cnt : std_logic_vector(4 downto 0);
    signal out_burst_cnt : std_logic_vector(3 downto 0);
    signal out_word_active : std_logic;
    signal required_words_for_write : std_logic_vector(5 downto 0);
	 signal burst_word_counter : std_logic_vector(4 downto 0);
    signal wr_data_has_space : std_logic;
    alias cmd_operation_type_ra : std_logic is exec_cmd_r(61);
    alias cmd_address_ra : std_logic_vector(24 downto 0) is exec_cmd_r(60 downto 36);
    alias cmd_datawidth_ra : std_logic_vector(11 downto 0) is exec_cmd_r(35 downto 24);
    alias cmd_be_first_ra : std_logic_vector(7 downto 0) is exec_cmd_r(23 downto 16);
    alias cmd_be_last_ra : std_logic_vector(7 downto 0) is exec_cmd_r(15 downto 8);
    alias cmd_operation_id_ra : std_logic_vector(7 downto 0) is exec_cmd_r(7 downto 0);

    function calc_be_bytes(be : std_logic_vector(7 downto 0)) return std_logic_vector is
        variable ones_cnt : integer := 0;
    begin
        for i in 0 to 7 loop
            if be(i) = '1' then
                ones_cnt := ones_cnt + 1;
            end if;
        end loop;
        return conv_std_logic_vector(ones_cnt, 4);
    end function;

    function calc_data_width(
        be_first : std_logic_vector(7 downto 0);
        be_last : std_logic_vector(7 downto 0);
        burstcnt : std_logic_vector(4 downto 0)
    ) return std_logic_vector is
        variable bytes_first : integer;
        variable bytes_last : integer;
        variable bytes_mid : integer;
        variable total_bytes : integer;
    begin
        bytes_first := conv_integer(calc_be_bytes(be_first));
        bytes_last := conv_integer(calc_be_bytes(be_last));
        if conv_integer(burstcnt) > 1 then
            bytes_mid := (conv_integer(burstcnt) - 2) * 8;
        else
            bytes_mid := 0;
        end if;
        total_bytes := bytes_first + bytes_mid + bytes_last;
        return conv_std_logic_vector(total_bytes, 12);
    end function;

begin
    wr_cmd_write <= wr_cmd_write_r;
    wr_data_write <= wr_data_write_r;
    rd_cmd_read <= rd_cmd_read_r;
    rd_data_read <= rd_data_read_r;
    read_data_avs <= read_data_r;
    waitrequest_avs <= '0' when (master_state = IDLE and (read_master = '0' and write_master = '0'))	
		  else'0' when (internal_state = READ_DATA and rd_data_empty = '0' and out_burst_cnt = "0000" and trans_cnt = "00001")
        else '0' when (master_state = WRITE_HEADER and avs_read_r = '1' and trans_cnt < "10000" and wr_cmd_full = '0' and avs_burstenable_r = '1') or (internal_state = READ_DATA and avs_burstenable_r = '0' and trans_cnt < "00010")
        else waitrequest_r when (avs_write_r = '1' or (avs_read_r = '1' and master_state /= IDLE))
        else '1';
        
    wr_data_has_space <= '1' when (WR_DATA_FIFO_DEPTH - conv_integer(wr_data_used)) >= conv_integer(required_words_for_write) else '0';
		
    master_fsm: process(clk_80MHz, nRST)
    begin
        if nRST = '0' then
            master_state <= IDLE;
        elsif rising_edge(clk_80MHz) then
            case master_state is
                when IDLE =>
                    if read_master = '1' then
                        if burstenable_master = '1' then
                            master_state <= BURST_READ;
                        else
                            master_state <= SINGLE_READ;
                        end if;
                    end if;
                    if write_master = '1' then
                        if burstenable_master = '1' then
                            master_state <= BURST_WRITE;
                        else
                            master_state <= SINGLE_WRITE;
                        end if;
                    end if;
                when SINGLE_READ => master_state <= PREPARE_HEADER;
                when SINGLE_WRITE => master_state <= PREPARE_HEADER;
                when BURST_READ => master_state <= PREPARE_HEADER;
                when BURST_WRITE => master_state <= PREPARE_HEADER;
                when PREPARE_HEADER =>
                    if wr_cmd_full = '0' and avs_read_r = '1' then
                        master_state <= WRITE_HEADER;
                    end if;
                    
                    if wr_cmd_full = '0' and wr_data_has_space = '1' then
                        if avs_write_r = '1' then
                            if avs_burstenable_r = '0' then
                                master_state <= WRITE_DATA;
                            else
                                master_state <= BURST_WRITE_DATA;
                            end if;
                        end if;
                    end if;
                when WRITE_HEADER =>
                    if avs_read_r = '1' then
						    if avs_burstenable_r = '0' then
							   master_state <= WAIT_READ_DATA;
							 else
                        master_state <= IDLE;
                      end if;
						  else
						    master_state <= IDLE;
                    end if;
                
                when WRITE_DATA =>
                    master_state <= WRITE_HEADER;
                when BURST_WRITE_DATA =>
                    if burst_write_words_sent >= burstcount_r + 1 then
                        master_state <= WRITE_HEADER;
                    end if;
                when WAIT_READ_DATA =>
                    if internal_state = READ_DATA and trans_cnt < "00010" then
                        master_state <= SEND_READ_DATA;
                    end if;
                when SEND_READ_DATA => master_state <= IDLE;
                when others => master_state <= IDLE;
            end case;
        end if;
    end process;

    internal_fsm: process(clk_80MHz, nRST)
    begin
        if nRST = '0' then
            internal_state <= IDLE;
        elsif rising_edge(clk_80MHz) then
            case internal_state is
                when IDLE =>
                    if rd_cmd_empty = '0' then
                        internal_state <= READ_HEADER;
                    end if;
                when READ_HEADER => internal_state <= PREPARE_ANSWER;
                when PREPARE_ANSWER => internal_state <= READ_DATA;
                when READ_DATA =>
                    if burst_rd_done = '1' then
                        internal_state <= IDLE;
                    end if;
                when others => internal_state <= IDLE;
            end case;
        end if;
    end process;

    signals: process(clk_80MHz, nRST)
    begin
        if nRST = '0' then
            read_data_r <= (others => '0');
            wr_cmd_write_r <= '0';
            wr_data_write_r <= '0';
            rd_cmd_read_r <= '0';
            rd_data_read_r <= '0';
            burst_rd_done <= '0';
            burst_write_words_sent <= (others => '0');
            exec_cmd_r <= (others => '0');
            wr_data <= (others => '0');
            avs_read_r <= '0';
            avs_write_r <= '0';
            read_data_valid <= '0';
            burst_queue <= (others => '0');
            q_wr_ptr <= (others => '0');
            q_rd_ptr <= (others => '0');
            trans_cnt <= (others => '0');
            out_burst_cnt <= (others => '0');
            out_word_active <= '0';
            required_words_for_write <= "000001";
				burst_word_counter <= (others => '0');
				led_control <= "00100100";
				op_id_cnt <= (others => '0');
        elsif rising_edge(clk_80MHz) then
		      led_control <= "00100100";
            if (master_state = IDLE and read_master = '1') then
                avs_read_r <= '1';
            elsif (master_state = WRITE_HEADER and avs_read_r = '1') then
                avs_read_r <= '0';
            end if;

            if (master_state = IDLE and write_master = '1') then
                avs_write_r <= '1';
            elsif (master_state = WRITE_HEADER) then
                avs_write_r <= '0';
            end if;

            if (master_state = IDLE and (read_master = '1' or write_master = '1')) then
				
                captured_addr_avalon_r <= address_master;
                captured_be_avalon_r <= byte_enable_master;
                captured_be_last_r <= byte_enable_master;
                avs_burstenable_r <= burstenable_master;
                burstcount_r <= burstcount_master;
					 burst_word_counter <= (others => '0');
            end if;
				
				if master_state = BURST_WRITE_DATA then
					if write_master = '1' and waitrequest_r = '0' then
						if burst_word_counter = "00000" then 
							burst_word_counter <= "00001";
						else 
							burst_word_counter <= burst_word_counter + 1;
						end if;
												
						if burst_word_counter = burstcount_r - 1 then
							captured_be_last_r <= byte_enable_master;
						end if;
						
						if burst_word_counter = burstcount_r then
							captured_be_last_r <= (others => '0');
						end if;
					end if;
				elsif master_state = IDLE then 
					burst_word_counter <= (others => '0');
				end if;
				
				if master_state = IDLE and write_master = '1' then 
				  if burstenable_master = '1' then
				    required_words_for_write <= "0" & burstcount_master;
				  else
				    required_words_for_write <= "000001";
				  end if;
				end if;

            if master_state = PREPARE_HEADER then
                cmd_operation_type_ra <= avs_write_r;
                cmd_address_ra <= captured_addr_avalon_r;
                cmd_be_first_ra <= captured_be_avalon_r;
                cmd_be_last_ra <= captured_be_last_r;
                cmd_operation_id_ra <= op_id_cnt;
					 op_id_cnt <= op_id_cnt + 1;
                if avs_burstenable_r = '0' then
                    cmd_datawidth_ra <= calc_data_width(captured_be_avalon_r, captured_be_avalon_r, "00001");
                else
                    cmd_datawidth_ra <= calc_data_width(captured_be_avalon_r, captured_be_last_r, burstcount_r);
                end if;
            end if;

            if (master_state = WRITE_HEADER and wr_cmd_full = '0') then
                wr_cmd_write_r <= '1';
					 wr_cmd <= exec_cmd_r;	
            else
                wr_cmd_write_r <= '0';
            end if;
				
            if (master_state = WRITE_DATA) then
                wr_data <= write_data_master;
            elsif (master_state = BURST_WRITE_DATA and write_master = '1' and burst_write_words_sent /= "00000" and burst_write_words_sent /= (burstcount_r + 1)) then
                wr_data <= write_data_master;
            end if;

            if (master_state = WRITE_DATA) then
                wr_data_write_r <= '1';
            elsif (master_state = BURST_WRITE_DATA and write_master = '1' and burst_write_words_sent /= "00000" and burst_write_words_sent /= (burstcount_r + 1)) then
                wr_data_write_r <= '1';
            else
                wr_data_write_r <= '0';
            end if;
            
            if master_state = WRITE_HEADER then
                burst_write_words_sent <= (others => '0');
            elsif (master_state = BURST_WRITE_DATA and write_master = '1') then
                if burst_write_words_sent = "00000" then
                    burst_write_words_sent <= burst_write_words_sent + 1;
                elsif burst_write_words_sent /= (burstcount_r + 1) then
                    burst_write_words_sent <= burst_write_words_sent + 1;
                end if;
            end if;

            if (master_state = WRITE_HEADER and avs_read_r = '1' and wr_cmd_full = '0') then
                burst_queue(conv_integer(q_wr_ptr)*4 + 3 downto conv_integer(q_wr_ptr)*4) <= burstcount_r(3 downto 0) - "0001";
            end if;

            if (master_state = WRITE_HEADER and avs_read_r = '1' and wr_cmd_full = '0') then
                if q_wr_ptr = "1111" then
                    q_wr_ptr <= "0000";
                else
                    q_wr_ptr <= q_wr_ptr + 1;
                end if;
            end if;

            if (master_state = WRITE_HEADER and avs_read_r = '1' and wr_cmd_full = '0') then
                trans_cnt <= trans_cnt + 1;
            elsif (internal_state = READ_DATA and trans_cnt > "00000" and burst_rd_done = '1') then
                trans_cnt <= trans_cnt - 1;
            end if;

            if (internal_state = READ_HEADER) then
                rd_cmd_read_r <= '1';
            else
                rd_cmd_read_r <= '0';
            end if;

            if (internal_state = READ_HEADER and out_word_active = '0') then
                out_word_active <= '1';
            elsif (internal_state = READ_DATA and out_burst_cnt = "0000") then
                out_word_active <= '0';
            end if;

            if (internal_state = READ_HEADER and out_word_active = '0') then
                out_burst_cnt <= burst_queue(conv_integer(q_rd_ptr)*4 + 3 downto conv_integer(q_rd_ptr)*4);
            elsif (internal_state = READ_DATA and out_burst_cnt /= "0000") then
                out_burst_cnt <= out_burst_cnt - 1;
            end if;

            if (internal_state = READ_DATA and trans_cnt > "00001") then
                read_data_valid <= '1';
            else
                read_data_valid <= '0';
            end if;

            if (internal_state = READ_DATA) then
                rd_data_read_r <= '1';
            else
                rd_data_read_r <= '0';
            end if;

            if (internal_state = READ_DATA) then
                read_data_r <= rd_data;
            end if;

            if (internal_state = READ_DATA and out_burst_cnt = "0000") then
                burst_rd_done <= '1';
            else
                burst_rd_done <= '0';
            end if;

            if (internal_state = READ_DATA and out_burst_cnt = "0000") then
                if q_rd_ptr = "1111" then
                    q_rd_ptr <= "0000";
                else
                    q_rd_ptr <= q_rd_ptr + 1;
                end if;
            end if;
            
            if (master_state = PREPARE_HEADER and avs_write_r = '1' and wr_data_has_space = '0') then
                waitrequest_r <= '1';
            elsif (trans_cnt < "10000" and wr_cmd_full = '0' and (master_state = BURST_WRITE_DATA or master_state = WRITE_DATA)) then
                waitrequest_r <= '0';
            else
                waitrequest_r <= '1';
            end if;
        end if;
    end process;
end architecture rtl;
