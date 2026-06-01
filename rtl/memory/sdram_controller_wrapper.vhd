library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sdram_controller_wrapper is
    generic (
        ADDR_WIDTH       : positive := 26;
        DATA_WIDTH       : positive := 32;
        EMULATED_WORDS   : positive := 32768;
        SIMULATION_MODEL : boolean := true
    );
    port (
        clk : in std_logic;
        rst : in std_logic;

        cmd_valid : in std_logic;
        cmd_write : in std_logic;
        cmd_addr  : in unsigned(ADDR_WIDTH-1 downto 0);
        cmd_wdata : in std_logic_vector(DATA_WIDTH-1 downto 0);
        cmd_be    : in std_logic_vector((DATA_WIDTH/8)-1 downto 0);
        cmd_ready : out std_logic;

        rd_valid : out std_logic;
        rd_data  : out std_logic_vector(DATA_WIDTH-1 downto 0);
        busy     : out std_logic;

        dram_addr  : out std_logic_vector(12 downto 0);
        dram_ba    : out std_logic_vector(1 downto 0);
        dram_cas_n : out std_logic;
        dram_cke   : out std_logic;
        dram_clk   : out std_logic;
        dram_cs_n  : out std_logic;
        dram_dq    : inout std_logic_vector(15 downto 0);
        dram_ldqm  : out std_logic;
        dram_ras_n : out std_logic;
        dram_udqm  : out std_logic;
        dram_we_n  : out std_logic
    );
end entity sdram_controller_wrapper;

architecture rtl of sdram_controller_wrapper is

    constant BYTE_LANES : positive := DATA_WIDTH / 8;
    constant FULL_BE    : std_logic_vector(BYTE_LANES-1 downto 0) := (others => '1');

begin

    assert DATA_WIDTH = 32
        report "sdram_controller_wrapper assume barramento de 32 bits."
        severity failure;

    gen_emulated : if SIMULATION_MODEL generate
        type byte_ram_t is array (0 to EMULATED_WORDS-1) of std_logic_vector(7 downto 0);

        signal ram0 : byte_ram_t := (others => (others => '0'));
        signal ram1 : byte_ram_t := (others => (others => '0'));
        signal ram2 : byte_ram_t := (others => (others => '0'));
        signal ram3 : byte_ram_t := (others => (others => '0'));

        signal rd_valid_reg : std_logic := '0';
        signal rd_data_reg  : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');
        signal rd_word_reg  : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');
        signal rd_lane_reg  : natural range 0 to 3 := 0;
        signal rd_align_valid_reg : std_logic := '0';

        attribute ramstyle : string;
        attribute ramstyle of ram0 : signal is "M10K";
        attribute ramstyle of ram1 : signal is "M10K";
        attribute ramstyle of ram2 : signal is "M10K";
        attribute ramstyle of ram3 : signal is "M10K";
    begin
        cmd_ready <= '1';
        rd_valid  <= rd_valid_reg;
        rd_data   <= rd_data_reg;
        busy      <= '0';

        dram_addr  <= (others => '0');
        dram_ba    <= (others => '0');
        dram_cas_n <= '1';
        dram_cke   <= '1';
        dram_clk   <= clk;
        dram_cs_n  <= '1';
        dram_dq    <= (others => 'Z');
        dram_ldqm  <= '1';
        dram_ras_n <= '1';
        dram_udqm  <= '1';
        dram_we_n  <= '1';

        process(clk, rst)
            variable word_index : natural;
            variable byte_lane  : natural;
        begin
            if rst = '1' then
                rd_valid_reg <= '0';
                rd_data_reg  <= (others => '0');
                rd_word_reg  <= (others => '0');
                rd_lane_reg  <= 0;
                rd_align_valid_reg <= '0';

            elsif rising_edge(clk) then
                rd_valid_reg <= '0';
                rd_align_valid_reg <= '0';

                if rd_align_valid_reg = '1' then
                    case rd_lane_reg is
                        when 0 =>
                            rd_data_reg <= rd_word_reg;
                        when 1 =>
                            rd_data_reg <= (31 downto 8 => '0') & rd_word_reg(15 downto 8);
                        when 2 =>
                            rd_data_reg <= (31 downto 8 => '0') & rd_word_reg(23 downto 16);
                        when others =>
                            rd_data_reg <= (31 downto 8 => '0') & rd_word_reg(31 downto 24);
                    end case;

                    rd_valid_reg <= '1';
                end if;

                if cmd_valid = '1' then
                    word_index := to_integer(cmd_addr) / BYTE_LANES;
                    byte_lane  := to_integer(cmd_addr) mod BYTE_LANES;

                    if word_index < EMULATED_WORDS then
                        if cmd_write = '1' then
                            if cmd_be = FULL_BE and byte_lane = 0 then
                                ram0(word_index) <= cmd_wdata(7 downto 0);
                                ram1(word_index) <= cmd_wdata(15 downto 8);
                                ram2(word_index) <= cmd_wdata(23 downto 16);
                                ram3(word_index) <= cmd_wdata(31 downto 24);
                            elsif cmd_be(0) = '1' then
                                case byte_lane is
                                    when 0 =>
                                        ram0(word_index) <= cmd_wdata(7 downto 0);
                                    when 1 =>
                                        ram1(word_index) <= cmd_wdata(7 downto 0);
                                    when 2 =>
                                        ram2(word_index) <= cmd_wdata(7 downto 0);
                                    when others =>
                                        ram3(word_index) <= cmd_wdata(7 downto 0);
                                end case;
                            end if;
                        else
                            rd_word_reg(7 downto 0)   <= ram0(word_index);
                            rd_word_reg(15 downto 8)  <= ram1(word_index);
                            rd_word_reg(23 downto 16) <= ram2(word_index);
                            rd_word_reg(31 downto 24) <= ram3(word_index);
                            rd_lane_reg <= byte_lane;
                            rd_align_valid_reg <= '1';
                        end if;
                    else
                        rd_data_reg  <= (others => '0');
                        rd_valid_reg <= not cmd_write;
                    end if;
                end if;
            end if;
        end process;
    end generate;

    gen_physical : if not SIMULATION_MODEL generate
        constant INIT_WAIT_CYCLES       : natural := 6000; -- >100 us @ 50 MHz
        constant REFRESH_INTERVAL_CYCLES : natural := 390; -- 7.8 us @ 50 MHz
        constant TRCD_CYCLES            : natural := 2;
        constant TRP_CYCLES             : natural := 2;
        constant TRFC_CYCLES            : natural := 4;
        constant TMRD_CYCLES            : natural := 2;
        constant TWR_CYCLES             : natural := 2;
        constant CAS_LATENCY_CYCLES     : natural := 2;

        type phy_state_t is (
            INIT_WAIT,
            INIT_PRECHARGE,
            INIT_TRP,
            INIT_REFRESH,
            INIT_RFC,
            INIT_MODE,
            INIT_MRD,
            READY,
            REFRESH_PRECHARGE,
            REFRESH_TRP,
            REFRESH_CMD,
            REFRESH_RFC,
            ACTIVATE,
            RCD_WAIT,
            READ_CMD,
            READ_WAIT,
            READ_CAPTURE,
            ACCESS_RECOVER,
            WRITE_CMD,
            WRITE_RECOVER
        );

        signal state : phy_state_t := INIT_WAIT;
        signal wait_counter : natural range 0 to INIT_WAIT_CYCLES := INIT_WAIT_CYCLES;
        signal init_refresh_count : natural range 0 to 7 := 0;
        signal refresh_counter : natural range 0 to REFRESH_INTERVAL_CYCLES := REFRESH_INTERVAL_CYCLES;
        signal refresh_due : std_logic := '0';

        signal cmd_write_reg : std_logic := '0';
        signal cmd_addr_reg  : unsigned(ADDR_WIDTH-1 downto 0) := (others => '0');
        signal cmd_wdata_reg : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');
        signal cmd_be_reg    : std_logic_vector(BYTE_LANES-1 downto 0) := (others => '0');

        signal half_step : natural range 0 to 1 := 0;
        signal read_half0 : std_logic_vector(15 downto 0) := (others => '0');
        signal rd_valid_reg : std_logic := '0';
        signal rd_data_reg  : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');

        signal dram_addr_reg  : std_logic_vector(12 downto 0) := (others => '0');
        signal dram_ba_reg    : std_logic_vector(1 downto 0) := (others => '0');
        signal dram_cas_n_reg : std_logic := '1';
        signal dram_cs_n_reg  : std_logic := '1';
        signal dram_ldqm_reg  : std_logic := '1';
        signal dram_ras_n_reg : std_logic := '1';
        signal dram_udqm_reg  : std_logic := '1';
        signal dram_we_n_reg  : std_logic := '1';
        signal dq_out_reg     : std_logic_vector(15 downto 0) := (others => '0');
        signal dq_oe_reg      : std_logic := '0';

        function bit_or_zero(constant value : unsigned; constant idx : natural) return std_logic is
        begin
            if idx <= value'high then
                return value(idx);
            end if;
            return '0';
        end function;

        function current_half_addr(
            constant byte_addr  : unsigned;
            constant write_op   : std_logic;
            constant byte_en    : std_logic_vector;
            constant step_value : natural
        ) return unsigned is
            variable result : unsigned(ADDR_WIDTH-2 downto 0);
            variable half_index : natural;
        begin
            if write_op = '1' and byte_en /= FULL_BE then
                half_index := to_integer(byte_addr) / 2;
            else
                half_index := ((to_integer(byte_addr) / 4) * 2) + step_value;
            end if;

            result := to_unsigned(half_index, result'length);
            return result;
        end function;

        function sdram_row_addr(constant half_addr : unsigned) return std_logic_vector is
            variable result : std_logic_vector(12 downto 0) := (others => '0');
        begin
            for idx in 0 to 12 loop
                result(idx) := bit_or_zero(half_addr, idx + 12);
            end loop;
            return result;
        end function;

        function sdram_col_addr(
            constant half_addr : unsigned;
            constant auto_precharge : std_logic
        ) return std_logic_vector is
            variable result : std_logic_vector(12 downto 0) := (others => '0');
        begin
            for idx in 0 to 9 loop
                result(idx) := bit_or_zero(half_addr, idx);
            end loop;
            result(10) := auto_precharge;
            return result;
        end function;

        function sdram_bank_addr(constant half_addr : unsigned) return std_logic_vector is
            variable result : std_logic_vector(1 downto 0) := (others => '0');
        begin
            result(0) := bit_or_zero(half_addr, 10);
            result(1) := bit_or_zero(half_addr, 11);
            return result;
        end function;

        function aligned_read_data(
            constant low_half  : std_logic_vector(15 downto 0);
            constant high_half : std_logic_vector(15 downto 0);
            constant byte_addr : unsigned
        ) return std_logic_vector is
            variable result : std_logic_vector(31 downto 0) := (others => '0');
            variable lane   : natural range 0 to 3;
        begin
            lane := to_integer(byte_addr(1 downto 0));

            case lane is
                when 0 =>
                    result := high_half & low_half;
                when 1 =>
                    result(7 downto 0) := low_half(15 downto 8);
                when 2 =>
                    result(7 downto 0) := high_half(7 downto 0);
                when others =>
                    result(7 downto 0) := high_half(15 downto 8);
            end case;

            return result;
        end function;

        function needs_second_half(
            constant write_op : std_logic;
            constant byte_en  : std_logic_vector
        ) return boolean is
        begin
            if write_op = '0' then
                return true;
            end if;
            return byte_en = FULL_BE;
        end function;

        procedure set_nop(
            signal cs_n  : out std_logic;
            signal ras_n : out std_logic;
            signal cas_n : out std_logic;
            signal we_n  : out std_logic
        ) is
        begin
            cs_n  <= '0';
            ras_n <= '1';
            cas_n <= '1';
            we_n  <= '1';
        end procedure;

    begin
        cmd_ready <= '1' when state = READY and refresh_due = '0' else '0';
        rd_valid  <= rd_valid_reg;
        rd_data   <= rd_data_reg;
        busy      <= '1' when state /= READY or refresh_due = '1' else '0';

        dram_addr  <= dram_addr_reg;
        dram_ba    <= dram_ba_reg;
        dram_cas_n <= dram_cas_n_reg;
        dram_cke   <= '1';
        dram_clk   <= clk;
        dram_cs_n  <= dram_cs_n_reg;
        dram_dq    <= dq_out_reg when dq_oe_reg = '1' else (others => 'Z');
        dram_ldqm  <= dram_ldqm_reg;
        dram_ras_n <= dram_ras_n_reg;
        dram_udqm  <= dram_udqm_reg;
        dram_we_n  <= dram_we_n_reg;

        process(clk, rst)
            variable half_addr_v : unsigned(ADDR_WIDTH-2 downto 0);
        begin
            if rst = '1' then
                state <= INIT_WAIT;
                wait_counter <= INIT_WAIT_CYCLES;
                init_refresh_count <= 0;
                refresh_counter <= REFRESH_INTERVAL_CYCLES;
                refresh_due <= '0';
                cmd_write_reg <= '0';
                cmd_addr_reg <= (others => '0');
                cmd_wdata_reg <= (others => '0');
                cmd_be_reg <= (others => '0');
                half_step <= 0;
                read_half0 <= (others => '0');
                rd_valid_reg <= '0';
                rd_data_reg <= (others => '0');
                dram_addr_reg <= (others => '0');
                dram_ba_reg <= (others => '0');
                dram_cs_n_reg <= '1';
                dram_ras_n_reg <= '1';
                dram_cas_n_reg <= '1';
                dram_we_n_reg <= '1';
                dram_ldqm_reg <= '1';
                dram_udqm_reg <= '1';
                dq_out_reg <= (others => '0');
                dq_oe_reg <= '0';

            elsif rising_edge(clk) then
                set_nop(dram_cs_n_reg, dram_ras_n_reg, dram_cas_n_reg, dram_we_n_reg);
                dram_addr_reg <= (others => '0');
                dram_ba_reg <= (others => '0');
                dram_ldqm_reg <= '0';
                dram_udqm_reg <= '0';
                dq_oe_reg <= '0';
                rd_valid_reg <= '0';

                if state /= INIT_WAIT and state /= INIT_PRECHARGE and state /= INIT_TRP and
                   state /= INIT_REFRESH and state /= INIT_RFC and state /= INIT_MODE and
                   state /= INIT_MRD and refresh_due = '0' then
                    if refresh_counter = 0 then
                        refresh_due <= '1';
                    else
                        refresh_counter <= refresh_counter - 1;
                    end if;
                end if;

                half_addr_v := current_half_addr(cmd_addr_reg, cmd_write_reg, cmd_be_reg, half_step);

                case state is
                    when INIT_WAIT =>
                        dram_cs_n_reg <= '1';
                        if wait_counter = 0 then
                            state <= INIT_PRECHARGE;
                        else
                            wait_counter <= wait_counter - 1;
                        end if;

                    when INIT_PRECHARGE =>
                        dram_cs_n_reg  <= '0';
                        dram_ras_n_reg <= '0';
                        dram_cas_n_reg <= '1';
                        dram_we_n_reg  <= '0';
                        dram_addr_reg(10) <= '1';
                        wait_counter <= TRP_CYCLES;
                        state <= INIT_TRP;

                    when INIT_TRP =>
                        if wait_counter = 0 then
                            init_refresh_count <= 0;
                            state <= INIT_REFRESH;
                        else
                            wait_counter <= wait_counter - 1;
                        end if;

                    when INIT_REFRESH =>
                        dram_cs_n_reg  <= '0';
                        dram_ras_n_reg <= '0';
                        dram_cas_n_reg <= '0';
                        dram_we_n_reg  <= '1';
                        wait_counter <= TRFC_CYCLES;
                        state <= INIT_RFC;

                    when INIT_RFC =>
                        if wait_counter = 0 then
                            if init_refresh_count = 7 then
                                state <= INIT_MODE;
                            else
                                init_refresh_count <= init_refresh_count + 1;
                                state <= INIT_REFRESH;
                            end if;
                        else
                            wait_counter <= wait_counter - 1;
                        end if;

                    when INIT_MODE =>
                        dram_cs_n_reg  <= '0';
                        dram_ras_n_reg <= '0';
                        dram_cas_n_reg <= '0';
                        dram_we_n_reg  <= '0';
                        dram_addr_reg <= (others => '0');
                        dram_addr_reg(6 downto 4) <= "010"; -- CAS latency 2, burst length 1
                        wait_counter <= TMRD_CYCLES;
                        state <= INIT_MRD;

                    when INIT_MRD =>
                        if wait_counter = 0 then
                            refresh_counter <= REFRESH_INTERVAL_CYCLES;
                            refresh_due <= '0';
                            state <= READY;
                        else
                            wait_counter <= wait_counter - 1;
                        end if;

                    when READY =>
                        if refresh_due = '1' then
                            state <= REFRESH_PRECHARGE;
                        elsif cmd_valid = '1' then
                            cmd_write_reg <= cmd_write;
                            cmd_addr_reg  <= cmd_addr;
                            cmd_wdata_reg <= cmd_wdata;
                            cmd_be_reg    <= cmd_be;
                            half_step <= 0;
                            state <= ACTIVATE;
                        end if;

                    when REFRESH_PRECHARGE =>
                        dram_cs_n_reg  <= '0';
                        dram_ras_n_reg <= '0';
                        dram_cas_n_reg <= '1';
                        dram_we_n_reg  <= '0';
                        dram_addr_reg(10) <= '1';
                        wait_counter <= TRP_CYCLES;
                        state <= REFRESH_TRP;

                    when REFRESH_TRP =>
                        if wait_counter = 0 then
                            state <= REFRESH_CMD;
                        else
                            wait_counter <= wait_counter - 1;
                        end if;

                    when REFRESH_CMD =>
                        dram_cs_n_reg  <= '0';
                        dram_ras_n_reg <= '0';
                        dram_cas_n_reg <= '0';
                        dram_we_n_reg  <= '1';
                        wait_counter <= TRFC_CYCLES;
                        state <= REFRESH_RFC;

                    when REFRESH_RFC =>
                        if wait_counter = 0 then
                            refresh_counter <= REFRESH_INTERVAL_CYCLES;
                            refresh_due <= '0';
                            state <= READY;
                        else
                            wait_counter <= wait_counter - 1;
                        end if;

                    when ACTIVATE =>
                        half_addr_v := current_half_addr(cmd_addr_reg, cmd_write_reg, cmd_be_reg, half_step);
                        dram_cs_n_reg  <= '0';
                        dram_ras_n_reg <= '0';
                        dram_cas_n_reg <= '1';
                        dram_we_n_reg  <= '1';
                        dram_ba_reg    <= sdram_bank_addr(half_addr_v);
                        dram_addr_reg  <= sdram_row_addr(half_addr_v);
                        wait_counter <= TRCD_CYCLES;
                        state <= RCD_WAIT;

                    when RCD_WAIT =>
                        if wait_counter = 0 then
                            if cmd_write_reg = '1' then
                                state <= WRITE_CMD;
                            else
                                state <= READ_CMD;
                            end if;
                        else
                            wait_counter <= wait_counter - 1;
                        end if;

                    when READ_CMD =>
                        half_addr_v := current_half_addr(cmd_addr_reg, cmd_write_reg, cmd_be_reg, half_step);
                        dram_cs_n_reg  <= '0';
                        dram_ras_n_reg <= '1';
                        dram_cas_n_reg <= '0';
                        dram_we_n_reg  <= '1';
                        dram_ba_reg    <= sdram_bank_addr(half_addr_v);
                        dram_addr_reg  <= sdram_col_addr(half_addr_v, '1');
                        wait_counter <= CAS_LATENCY_CYCLES;
                        state <= READ_WAIT;

                    when READ_WAIT =>
                        if wait_counter = 0 then
                            state <= READ_CAPTURE;
                        else
                            wait_counter <= wait_counter - 1;
                        end if;

                    when READ_CAPTURE =>
                        if half_step = 0 then
                            read_half0 <= dram_dq;
                        else
                            rd_data_reg <= aligned_read_data(read_half0, dram_dq, cmd_addr_reg);
                            rd_valid_reg <= '1';
                        end if;

                        wait_counter <= TRP_CYCLES;
                        state <= ACCESS_RECOVER;

                    when ACCESS_RECOVER =>
                        if wait_counter = 0 then
                            if half_step = 0 then
                                half_step <= 1;
                                state <= ACTIVATE;
                            else
                                state <= READY;
                            end if;
                        else
                            wait_counter <= wait_counter - 1;
                        end if;

                    when WRITE_CMD =>
                        half_addr_v := current_half_addr(cmd_addr_reg, cmd_write_reg, cmd_be_reg, half_step);
                        dram_cs_n_reg  <= '0';
                        dram_ras_n_reg <= '1';
                        dram_cas_n_reg <= '0';
                        dram_we_n_reg  <= '0';
                        dram_ba_reg    <= sdram_bank_addr(half_addr_v);
                        dram_addr_reg  <= sdram_col_addr(half_addr_v, '1');
                        dq_oe_reg <= '1';

                        if cmd_be_reg = FULL_BE then
                            if half_step = 0 then
                                dq_out_reg <= cmd_wdata_reg(15 downto 0);
                                dram_ldqm_reg <= not cmd_be_reg(0);
                                dram_udqm_reg <= not cmd_be_reg(1);
                            else
                                dq_out_reg <= cmd_wdata_reg(31 downto 16);
                                dram_ldqm_reg <= not cmd_be_reg(2);
                                dram_udqm_reg <= not cmd_be_reg(3);
                            end if;
                        else
                            if cmd_addr_reg(0) = '0' then
                                dq_out_reg(7 downto 0) <= cmd_wdata_reg(7 downto 0);
                                dq_out_reg(15 downto 8) <= (others => '0');
                                dram_ldqm_reg <= '0';
                                dram_udqm_reg <= '1';
                            else
                                dq_out_reg(7 downto 0) <= (others => '0');
                                dq_out_reg(15 downto 8) <= cmd_wdata_reg(7 downto 0);
                                dram_ldqm_reg <= '1';
                                dram_udqm_reg <= '0';
                            end if;
                        end if;

                        wait_counter <= TWR_CYCLES + TRP_CYCLES;
                        state <= WRITE_RECOVER;

                    when WRITE_RECOVER =>
                        if wait_counter = 0 then
                            if half_step = 0 and needs_second_half(cmd_write_reg, cmd_be_reg) then
                                half_step <= 1;
                                state <= ACTIVATE;
                            else
                                state <= READY;
                            end if;
                        else
                            wait_counter <= wait_counter - 1;
                        end if;
                end case;
            end if;
        end process;
    end generate;

end architecture rtl;
