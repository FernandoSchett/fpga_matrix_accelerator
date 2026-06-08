library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sdram_controller_wrapper is
    generic (
        ADDR_WIDTH       : positive := 26;
        DATA_WIDTH       : positive := 32;
        EMULATED_WORDS   : positive := 32768;
        SIMULATION_MODEL : boolean := true;
        READ_TIMEOUT_CYCLES : natural := 100000
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
        error    : out std_logic;

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
        report "sdram_controller_wrapper assume barramento interno de 32 bits."
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
        error     <= '0';

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

    gen_physical_ip : if not SIMULATION_MODEL generate
        component sdram_ip_core is
            port (
                clk                : in std_logic;
                reset_n            : in std_logic;
                az_addr            : in std_logic_vector(ADDR_WIDTH-2 downto 0);
                az_be_n            : in std_logic_vector(1 downto 0);
                az_cs              : in std_logic;
                az_data            : in std_logic_vector(15 downto 0);
                az_rd_n            : in std_logic;
                az_wr_n            : in std_logic;
                za_data            : out std_logic_vector(15 downto 0);
                za_valid           : out std_logic;
                za_waitrequest     : out std_logic;
                zs_addr            : out std_logic_vector(12 downto 0);
                zs_ba              : out std_logic_vector(1 downto 0);
                zs_cas_n           : out std_logic;
                zs_cke             : out std_logic;
                zs_cs_n            : out std_logic;
                zs_dq              : inout std_logic_vector(15 downto 0);
                zs_dqm             : out std_logic_vector(1 downto 0);
                zs_ras_n           : out std_logic;
                zs_we_n            : out std_logic
            );
        end component;

        type state_t is (IDLE, ISSUE_HALF, WAIT_READ_DATA);

        signal state : state_t := IDLE;

        signal cmd_write_reg : std_logic := '0';
        signal cmd_addr_reg  : unsigned(ADDR_WIDTH-1 downto 0) := (others => '0');
        signal cmd_wdata_reg : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');
        signal cmd_be_reg    : std_logic_vector(BYTE_LANES-1 downto 0) := (others => '0');
        signal half_step     : natural range 0 to 1 := 0;
        signal half_count    : natural range 1 to 2 := 1;
        signal byte_only     : std_logic := '0';

        signal read_low_half : std_logic_vector(15 downto 0) := (others => '0');
        signal rd_valid_reg  : std_logic := '0';
        signal rd_data_reg   : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');
        signal error_reg     : std_logic := '0';
        signal read_timeout_counter : natural range 0 to READ_TIMEOUT_CYCLES := 0;

        signal ip_addr        : std_logic_vector(ADDR_WIDTH-2 downto 0) := (others => '0');
        signal ip_be_n        : std_logic_vector(1 downto 0) := (others => '1');
        signal ip_cs          : std_logic := '0';
        signal ip_wdata       : std_logic_vector(15 downto 0) := (others => '0');
        signal ip_rd_n        : std_logic := '1';
        signal ip_wr_n        : std_logic := '1';
        signal ip_rdata       : std_logic_vector(15 downto 0);
        signal ip_valid       : std_logic;
        signal ip_waitrequest : std_logic;
        signal ip_dqm         : std_logic_vector(1 downto 0);

        function is_full_word(
            constant byte_addr : unsigned;
            constant be_value  : std_logic_vector
        ) return boolean is
        begin
            return byte_addr(1 downto 0) = "00" and be_value = FULL_BE;
        end function;

        function read_needs_word(constant byte_addr : unsigned) return boolean is
        begin
            return byte_addr(1 downto 0) = "00";
        end function;

        function half_addr(
            constant byte_addr : unsigned;
            constant step      : natural
        ) return std_logic_vector is
            variable result : unsigned(ADDR_WIDTH-2 downto 0);
        begin
            result := byte_addr(ADDR_WIDTH-1 downto 1);
            if step = 1 then
                result := result + 1;
            end if;
            return std_logic_vector(result);
        end function;

        function write_half_data(
            constant byte_addr : unsigned;
            constant wdata     : std_logic_vector;
            constant be_value  : std_logic_vector;
            constant step      : natural
        ) return std_logic_vector is
            variable result : std_logic_vector(15 downto 0) := (others => '0');
        begin
            if is_full_word(byte_addr, be_value) then
                if step = 0 then
                    result := wdata(15 downto 0);
                else
                    result := wdata(31 downto 16);
                end if;
            elsif byte_addr(0) = '0' then
                result(7 downto 0) := wdata(7 downto 0);
            else
                result(15 downto 8) := wdata(7 downto 0);
            end if;
            return result;
        end function;

        function write_half_be_n(
            constant byte_addr : unsigned;
            constant be_value  : std_logic_vector;
            constant step      : natural
        ) return std_logic_vector is
            variable result : std_logic_vector(1 downto 0) := (others => '1');
        begin
            if is_full_word(byte_addr, be_value) then
                if step = 0 then
                    result(0) := not be_value(0);
                    result(1) := not be_value(1);
                else
                    result(0) := not be_value(2);
                    result(1) := not be_value(3);
                end if;
            elsif byte_addr(0) = '0' then
                result := "10";
            else
                result := "01";
            end if;
            return result;
        end function;

        function align_byte_read(
            constant half_data : std_logic_vector;
            constant byte_addr : unsigned
        ) return std_logic_vector is
            variable result : std_logic_vector(31 downto 0) := (others => '0');
        begin
            if byte_addr(0) = '0' then
                result(7 downto 0) := half_data(7 downto 0);
            else
                result(7 downto 0) := half_data(15 downto 8);
            end if;
            return result;
        end function;

    begin
        cmd_ready <= '1' when state = IDLE and ip_waitrequest = '0' else '0';
        rd_valid  <= rd_valid_reg;
        rd_data   <= rd_data_reg;
        busy      <= '1' when state /= IDLE or ip_waitrequest = '1' else '0';
        error     <= error_reg;

        dram_clk  <= clk;
        dram_ldqm <= ip_dqm(0);
        dram_udqm <= ip_dqm(1);

        ip_cs    <= '1' when state = ISSUE_HALF else '0';
        ip_rd_n  <= '0' when state = ISSUE_HALF and cmd_write_reg = '0' else '1';
        ip_wr_n  <= '0' when state = ISSUE_HALF and cmd_write_reg = '1' else '1';
        ip_addr  <= half_addr(cmd_addr_reg, half_step) when state = ISSUE_HALF else (others => '0');
        ip_wdata <= write_half_data(cmd_addr_reg, cmd_wdata_reg, cmd_be_reg, half_step);
        ip_be_n  <= write_half_be_n(cmd_addr_reg, cmd_be_reg, half_step) when cmd_write_reg = '1' else "00";

        u_sdram_ip : sdram_ip_core
            port map (
                clk            => clk,
                reset_n        => not rst,
                az_addr        => ip_addr,
                az_be_n        => ip_be_n,
                az_cs          => ip_cs,
                az_data        => ip_wdata,
                az_rd_n        => ip_rd_n,
                az_wr_n        => ip_wr_n,
                za_data        => ip_rdata,
                za_valid       => ip_valid,
                za_waitrequest => ip_waitrequest,
                zs_addr        => dram_addr,
                zs_ba          => dram_ba,
                zs_cas_n       => dram_cas_n,
                zs_cke         => dram_cke,
                zs_cs_n        => dram_cs_n,
                zs_dq          => dram_dq,
                zs_dqm         => ip_dqm,
                zs_ras_n       => dram_ras_n,
                zs_we_n        => dram_we_n
            );

        process(clk, rst)
        begin
            if rst = '1' then
                state <= IDLE;
                cmd_write_reg <= '0';
                cmd_addr_reg  <= (others => '0');
                cmd_wdata_reg <= (others => '0');
                cmd_be_reg    <= (others => '0');
                half_step     <= 0;
                half_count    <= 1;
                byte_only     <= '0';
                read_low_half <= (others => '0');
                rd_valid_reg  <= '0';
                rd_data_reg   <= (others => '0');
                error_reg     <= '0';
                read_timeout_counter <= 0;

            elsif rising_edge(clk) then
                rd_valid_reg <= '0';

                case state is
                    when IDLE =>
                        read_timeout_counter <= 0;
                        if cmd_valid = '1' and ip_waitrequest = '0' then
                            cmd_write_reg <= cmd_write;
                            cmd_addr_reg  <= cmd_addr;
                            cmd_wdata_reg <= cmd_wdata;
                            cmd_be_reg    <= cmd_be;
                            half_step     <= 0;

                            if cmd_write = '1' then
                                if is_full_word(cmd_addr, cmd_be) then
                                    half_count <= 2;
                                else
                                    half_count <= 1;
                                end if;
                                byte_only <= '0';
                            else
                                if read_needs_word(cmd_addr) then
                                    half_count <= 2;
                                    byte_only  <= '0';
                                else
                                    half_count <= 1;
                                    byte_only  <= '1';
                                end if;
                            end if;

                            state <= ISSUE_HALF;
                        end if;

                    when ISSUE_HALF =>
                        read_timeout_counter <= 0;
                        if ip_waitrequest = '0' then
                            if cmd_write_reg = '1' then
                                if half_step = 0 and half_count = 2 then
                                    half_step <= 1;
                                else
                                    state <= IDLE;
                                end if;
                            else
                                state <= WAIT_READ_DATA;
                            end if;
                        end if;

                    when WAIT_READ_DATA =>
                        if ip_valid = '1' then
                            read_timeout_counter <= 0;
                            if half_step = 0 and half_count = 2 then
                                read_low_half <= ip_rdata;
                                half_step <= 1;
                                state <= ISSUE_HALF;
                            else
                                if byte_only = '1' then
                                    rd_data_reg <= align_byte_read(ip_rdata, cmd_addr_reg);
                                else
                                    rd_data_reg <= ip_rdata & read_low_half;
                                end if;
                                rd_valid_reg <= '1';
                                state <= IDLE;
                            end if;
                        elsif read_timeout_counter = READ_TIMEOUT_CYCLES then
                            rd_data_reg <= x"DEAD0001";
                            rd_valid_reg <= '1';
                            error_reg <= '1';
                            read_timeout_counter <= 0;
                            state <= IDLE;
                        else
                            read_timeout_counter <= read_timeout_counter + 1;
                        end if;
                end case;
            end if;
        end process;
    end generate;

end architecture rtl;
