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
        USE_SIM_SDRAM    : boolean := true
    );
    port (
        clk : in std_logic;
        rst : in std_logic;

        host_req     : in std_logic;
        host_we      : in std_logic;
        host_addr    : in unsigned(SDRAM_ADDR_WIDTH-1 downto 0);
        host_wdata   : in std_logic_vector(SDRAM_DATA_WIDTH-1 downto 0);
        host_byte_en : in std_logic_vector((SDRAM_DATA_WIDTH/8)-1 downto 0);
        host_ready   : out std_logic;
        host_rvalid  : out std_logic;
        host_rdata   : out std_logic_vector(SDRAM_DATA_WIDTH-1 downto 0);

        start : in std_logic;
        busy  : out std_logic;
        done  : out std_logic;

        perf_cycles       : out unsigned(63 downto 0);
        perf_sdram_reads  : out unsigned(63 downto 0);
        perf_sdram_writes : out unsigned(63 downto 0);
        perf_mac_groups   : out unsigned(63 downto 0)
    );
end entity matrix_accelerator_sdram_core_top;

architecture rtl of matrix_accelerator_sdram_core_top is

    signal ctrl_req     : std_logic;
    signal ctrl_we      : std_logic;
    signal ctrl_addr    : unsigned(SDRAM_ADDR_WIDTH-1 downto 0);
    signal ctrl_wdata   : std_logic_vector(SDRAM_DATA_WIDTH-1 downto 0);
    signal ctrl_byte_en : std_logic_vector((SDRAM_DATA_WIDTH/8)-1 downto 0);
    signal ctrl_ready   : std_logic;
    signal ctrl_rvalid  : std_logic;
    signal ctrl_rdata   : std_logic_vector(SDRAM_DATA_WIDTH-1 downto 0);

    signal selected_req     : std_logic;
    signal selected_we      : std_logic;
    signal selected_addr    : unsigned(SDRAM_ADDR_WIDTH-1 downto 0);
    signal selected_wdata   : std_logic_vector(SDRAM_DATA_WIDTH-1 downto 0);
    signal selected_byte_en : std_logic_vector((SDRAM_DATA_WIDTH/8)-1 downto 0);
    signal selected_ready   : std_logic;
    signal selected_rvalid  : std_logic;
    signal selected_rdata   : std_logic_vector(SDRAM_DATA_WIDTH-1 downto 0);

    signal mem_req     : std_logic;
    signal mem_we      : std_logic;
    signal mem_addr    : unsigned(SDRAM_ADDR_WIDTH-1 downto 0);
    signal mem_wdata   : std_logic_vector(SDRAM_DATA_WIDTH-1 downto 0);
    signal mem_byte_en : std_logic_vector((SDRAM_DATA_WIDTH/8)-1 downto 0);
    signal mem_ready   : std_logic;
    signal mem_rvalid  : std_logic;
    signal mem_rdata   : std_logic_vector(SDRAM_DATA_WIDTH-1 downto 0);

    signal busy_int : std_logic;
    signal done_int : std_logic;
    signal ctrl_active : std_logic;

    signal event_sdram_read  : std_logic;
    signal event_sdram_write : std_logic;
    signal event_mac_group   : std_logic;

begin

    busy <= busy_int;
    done <= done_int;

    ctrl_active <= busy_int or start;

    selected_req     <= ctrl_req when ctrl_active = '1' else host_req;
    selected_we      <= ctrl_we when ctrl_active = '1' else host_we;
    selected_addr    <= ctrl_addr when ctrl_active = '1' else host_addr;
    selected_wdata   <= ctrl_wdata when ctrl_active = '1' else host_wdata;
    selected_byte_en <= ctrl_byte_en when ctrl_active = '1' else host_byte_en;

    ctrl_ready  <= selected_ready when ctrl_active = '1' else '0';
    ctrl_rvalid <= selected_rvalid when ctrl_active = '1' else '0';
    ctrl_rdata  <= selected_rdata;

    host_ready  <= selected_ready when ctrl_active = '0' else '0';
    host_rvalid <= selected_rvalid when ctrl_active = '0' else '0';
    host_rdata  <= selected_rdata;

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
            sdram_req         => ctrl_req,
            sdram_we          => ctrl_we,
            sdram_addr        => ctrl_addr,
            sdram_wdata       => ctrl_wdata,
            sdram_byte_en     => ctrl_byte_en,
            sdram_ready       => ctrl_ready,
            sdram_rvalid      => ctrl_rvalid,
            sdram_rdata       => ctrl_rdata,
            event_sdram_read  => event_sdram_read,
            event_sdram_write => event_sdram_write,
            event_mac_group   => event_mac_group
        );

    u_bus_if : entity work.sdram_bus_if
        generic map (
            DATA_WIDTH => SDRAM_DATA_WIDTH,
            ADDR_WIDTH => SDRAM_ADDR_WIDTH
        )
        port map (
            client_req     => selected_req,
            client_we      => selected_we,
            client_addr    => selected_addr,
            client_wdata   => selected_wdata,
            client_byte_en => selected_byte_en,
            client_ready   => selected_ready,
            client_rvalid  => selected_rvalid,
            client_rdata   => selected_rdata,
            mem_req        => mem_req,
            mem_we         => mem_we,
            mem_addr       => mem_addr,
            mem_wdata      => mem_wdata,
            mem_byte_en    => mem_byte_en,
            mem_ready      => mem_ready,
            mem_rvalid     => mem_rvalid,
            mem_rdata      => mem_rdata
        );

    gen_sim_sdram : if USE_SIM_SDRAM generate
        u_sdram : entity work.sdram_sim_wrapper
            generic map (
                DATA_WIDTH => SDRAM_DATA_WIDTH,
                ADDR_WIDTH => SDRAM_ADDR_WIDTH,
                DEPTH      => SDRAM_DEPTH
            )
            port map (
                clk     => clk,
                rst     => rst,
                req     => mem_req,
                we      => mem_we,
                addr    => mem_addr,
                wdata   => mem_wdata,
                byte_en => mem_byte_en,
                ready   => mem_ready,
                rvalid  => mem_rvalid,
                rdata   => mem_rdata
            );
    end generate;

    gen_ip_sdram : if not USE_SIM_SDRAM generate
        u_sdram : entity work.sdram_ip_wrapper
            generic map (
                DATA_WIDTH => SDRAM_DATA_WIDTH,
                ADDR_WIDTH => SDRAM_ADDR_WIDTH
            )
            port map (
                clk     => clk,
                rst     => rst,
                req     => mem_req,
                we      => mem_we,
                addr    => mem_addr,
                wdata   => mem_wdata,
                byte_en => mem_byte_en,
                ready   => mem_ready,
                rvalid  => mem_rvalid,
                rdata   => mem_rdata
            );
    end generate;

    u_perf : entity work.perf_counters
        generic map (
            COUNTER_WIDTH => 64
        )
        port map (
            clk               => clk,
            rst               => rst,
            clear             => start,
            enable            => busy_int,
            event_sdram_read  => event_sdram_read,
            event_sdram_write => event_sdram_write,
            event_mac_group   => event_mac_group,
            cycle_count       => perf_cycles,
            sdram_read_count  => perf_sdram_reads,
            sdram_write_count => perf_sdram_writes,
            mac_group_count   => perf_mac_groups
        );

end architecture rtl;
