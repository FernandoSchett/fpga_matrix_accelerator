library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.matrix_accel_config_pkg.all;

entity matrix_accelerator_sdram_core_top is
    generic (
        N                : positive := DEFAULT_N;
        TILE_SIZE        : positive := DEFAULT_TILE_SIZE;
        NUM_MACS         : positive := DEFAULT_NUM_MACS;
        DATA_WIDTH       : positive := DEFAULT_DATA_WIDTH;
        ACC_WIDTH        : positive := DEFAULT_ACC_WIDTH;
        SDRAM_DATA_WIDTH : positive := DEFAULT_SDRAM_DATA_WIDTH;
        SDRAM_ADDR_WIDTH : positive := DEFAULT_SDRAM_ADDR_WIDTH;
        SDRAM_DEPTH      : positive := 262144;
        READ_LATENCY     : natural  := 3;
        WRITE_LATENCY    : natural  := 2
    );
    port (
        clk : in std_logic;
        rst : in std_logic;

        host_wr_en     : in std_logic;
        host_matrix_sel : in std_logic_vector(1 downto 0);
        host_addr      : in unsigned(SDRAM_ADDR_WIDTH-1 downto 0);
        host_data_in   : in std_logic_vector(SDRAM_DATA_WIDTH-1 downto 0);

        host_rd_en     : in std_logic;
        host_rd_addr   : in unsigned(SDRAM_ADDR_WIDTH-1 downto 0);
        host_data_out  : out std_logic_vector(SDRAM_DATA_WIDTH-1 downto 0);

        start : in std_logic;
        busy  : out std_logic;
        done  : out std_logic;

        perf_total_cycles        : out unsigned(63 downto 0);
        perf_load_cycles         : out unsigned(63 downto 0);
        perf_compute_cycles      : out unsigned(63 downto 0);
        perf_store_cycles        : out unsigned(63 downto 0);
        perf_num_tiles_processed : out unsigned(63 downto 0);
        perf_num_mac_ops_issued  : out unsigned(63 downto 0)
    );
end entity matrix_accelerator_sdram_core_top;

architecture rtl of matrix_accelerator_sdram_core_top is

    constant MATRIX_ELEMS : natural := N * N;
    constant BASE_A       : natural := 0;
    constant BASE_B       : natural := MATRIX_ELEMS;
    constant BASE_C       : natural := MATRIX_ELEMS * 2;

    type host_state_t is (
        HOST_IDLE,
        HOST_WAIT_WRITE,
        HOST_WAIT_READ
    );

    signal ctrl_rd_req   : std_logic;
    signal ctrl_rd_addr  : unsigned(SDRAM_ADDR_WIDTH-1 downto 0);
    signal ctrl_rd_data  : std_logic_vector(SDRAM_DATA_WIDTH-1 downto 0);
    signal ctrl_rd_valid : std_logic;
    signal ctrl_rd_ready : std_logic;
    signal ctrl_wr_req   : std_logic;
    signal ctrl_wr_addr  : unsigned(SDRAM_ADDR_WIDTH-1 downto 0);
    signal ctrl_wr_data  : std_logic_vector(SDRAM_DATA_WIDTH-1 downto 0);
    signal ctrl_wr_ready : std_logic;
    signal ctrl_sdram_busy : std_logic;

    signal selected_rd_req   : std_logic;
    signal selected_rd_addr  : unsigned(SDRAM_ADDR_WIDTH-1 downto 0);
    signal selected_rd_data  : std_logic_vector(SDRAM_DATA_WIDTH-1 downto 0);
    signal selected_rd_valid : std_logic;
    signal selected_rd_ready : std_logic;
    signal selected_wr_req   : std_logic;
    signal selected_wr_addr  : unsigned(SDRAM_ADDR_WIDTH-1 downto 0);
    signal selected_wr_data  : std_logic_vector(SDRAM_DATA_WIDTH-1 downto 0);
    signal selected_wr_ready : std_logic;
    signal selected_busy     : std_logic;

    signal host_state        : host_state_t := HOST_IDLE;
    signal host_rd_req_reg   : std_logic := '0';
    signal host_rd_addr_reg  : unsigned(SDRAM_ADDR_WIDTH-1 downto 0) := (others => '0');
    signal host_wr_req_reg   : std_logic := '0';
    signal host_wr_addr_reg  : unsigned(SDRAM_ADDR_WIDTH-1 downto 0) := (others => '0');
    signal host_wr_data_reg  : std_logic_vector(SDRAM_DATA_WIDTH-1 downto 0) := (others => '0');
    signal host_data_out_reg : std_logic_vector(SDRAM_DATA_WIDTH-1 downto 0) := (others => '0');

    signal busy_int : std_logic;
    signal done_int : std_logic;
    signal ctrl_active : std_logic;

    signal event_sdram_read  : std_logic;
    signal event_sdram_write : std_logic;
    signal event_mac_group   : std_logic;

    function host_base(
        constant matrix_sel : std_logic_vector(1 downto 0)
    ) return unsigned is
        variable base_nat : natural;
    begin
        if matrix_sel = MATRIX_ID_A then
            base_nat := BASE_A;
        elsif matrix_sel = MATRIX_ID_B then
            base_nat := BASE_B;
        else
            base_nat := BASE_C;
        end if;

        return to_unsigned(base_nat, SDRAM_ADDR_WIDTH);
    end function;

begin

    busy <= busy_int;
    done <= done_int;
    host_data_out <= host_data_out_reg;

    ctrl_active <= busy_int or start;

    selected_rd_req  <= ctrl_rd_req when ctrl_active = '1' else host_rd_req_reg;
    selected_rd_addr <= ctrl_rd_addr when ctrl_active = '1' else host_rd_addr_reg;
    selected_wr_req  <= ctrl_wr_req when ctrl_active = '1' else host_wr_req_reg;
    selected_wr_addr <= ctrl_wr_addr when ctrl_active = '1' else host_wr_addr_reg;
    selected_wr_data <= ctrl_wr_data when ctrl_active = '1' else host_wr_data_reg;

    ctrl_rd_data  <= selected_rd_data;
    ctrl_rd_valid <= selected_rd_valid when ctrl_active = '1' else '0';
    ctrl_rd_ready <= selected_rd_ready when ctrl_active = '1' else '0';
    ctrl_wr_ready <= selected_wr_ready when ctrl_active = '1' else '0';
    ctrl_sdram_busy <= selected_busy when ctrl_active = '1' else '1';

    u_controller : entity work.accelerator_controller
        generic map (
            N                => N,
            TILE_SIZE        => TILE_SIZE,
            NUM_MACS         => NUM_MACS,
            DATA_WIDTH       => DATA_WIDTH,
            ACC_WIDTH        => ACC_WIDTH,
            SDRAM_DATA_WIDTH => SDRAM_DATA_WIDTH,
            SDRAM_ADDR_WIDTH => SDRAM_ADDR_WIDTH
        )
        port map (
            clk               => clk,
            rst               => rst,
            start             => start,
            busy              => busy_int,
            done              => done_int,
            sdram_rd_req      => ctrl_rd_req,
            sdram_rd_addr     => ctrl_rd_addr,
            sdram_rd_data     => ctrl_rd_data,
            sdram_rd_valid    => ctrl_rd_valid,
            sdram_rd_ready    => ctrl_rd_ready,
            sdram_wr_req      => ctrl_wr_req,
            sdram_wr_addr     => ctrl_wr_addr,
            sdram_wr_data     => ctrl_wr_data,
            sdram_wr_ready    => ctrl_wr_ready,
            sdram_busy        => ctrl_sdram_busy,
            event_sdram_read  => event_sdram_read,
            event_sdram_write => event_sdram_write,
            event_mac_group   => event_mac_group,
            perf_total_cycles        => perf_total_cycles,
            perf_load_cycles         => perf_load_cycles,
            perf_compute_cycles      => perf_compute_cycles,
            perf_store_cycles        => perf_store_cycles,
            perf_num_tiles_processed => perf_num_tiles_processed,
            perf_num_mac_ops_issued  => perf_num_mac_ops_issued
        );

    u_sdram : entity work.sdram_model
        generic map (
            DATA_WIDTH    => SDRAM_DATA_WIDTH,
            ADDR_WIDTH    => SDRAM_ADDR_WIDTH,
            READ_LATENCY  => READ_LATENCY,
            WRITE_LATENCY => WRITE_LATENCY,
            DEPTH         => SDRAM_DEPTH
        )
        port map (
            clk      => clk,
            rst      => rst,
            rd_req   => selected_rd_req,
            rd_addr  => selected_rd_addr,
            rd_data  => selected_rd_data,
            rd_valid => selected_rd_valid,
            rd_ready => selected_rd_ready,
            wr_req   => selected_wr_req,
            wr_addr  => selected_wr_addr,
            wr_data  => selected_wr_data,
            wr_ready => selected_wr_ready,
            busy     => selected_busy
        );

    process(clk, rst)
    begin
        if rst = '1' then
            host_state        <= HOST_IDLE;
            host_rd_req_reg   <= '0';
            host_rd_addr_reg  <= (others => '0');
            host_wr_req_reg   <= '0';
            host_wr_addr_reg  <= (others => '0');
            host_wr_data_reg  <= (others => '0');
            host_data_out_reg <= (others => '0');

        elsif rising_edge(clk) then
            host_rd_req_reg <= '0';
            host_wr_req_reg <= '0';

            case host_state is
                when HOST_IDLE =>
                    if ctrl_active = '0' then
                        if host_wr_en = '1' and selected_wr_ready = '1' then
                            host_wr_addr_reg <= host_base(host_matrix_sel) + host_addr;
                            host_wr_data_reg <= host_data_in;
                            host_wr_req_reg  <= '1';
                            host_state       <= HOST_WAIT_WRITE;

                        elsif host_rd_en = '1' and selected_rd_ready = '1' then
                            host_rd_addr_reg <= to_unsigned(BASE_C, SDRAM_ADDR_WIDTH) + host_rd_addr;
                            host_rd_req_reg  <= '1';
                            host_state       <= HOST_WAIT_READ;
                        end if;
                    end if;

                when HOST_WAIT_WRITE =>
                    if selected_wr_ready = '1' and selected_busy = '0' then
                        host_state <= HOST_IDLE;
                    end if;

                when HOST_WAIT_READ =>
                    if selected_rd_valid = '1' then
                        host_data_out_reg <= selected_rd_data;
                        host_state        <= HOST_IDLE;
                    end if;
            end case;
        end if;
    end process;

end architecture rtl;
