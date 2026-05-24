library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.matrix_accel_config_pkg.all;

entity matrix_accelerator_full_top is
    generic (
        N                : positive := DEFAULT_N;
        TILE_SIZE        : positive := DEFAULT_TILE_SIZE;
        NUM_MACS         : positive := DEFAULT_NUM_MACS;
        DATA_WIDTH       : positive := DEFAULT_DATA_WIDTH;
        ACC_WIDTH        : positive := DEFAULT_ACC_WIDTH;
        SDRAM_DATA_WIDTH : positive := DEFAULT_SDRAM_DATA_WIDTH;
        SDRAM_ADDR_WIDTH : positive := DEFAULT_SDRAM_ADDR_WIDTH;
        CLKS_PER_BIT     : positive := 434
    );
    port (
        clk : in std_logic;
        rst : in std_logic;

        uart_rx_i : in std_logic;
        uart_tx_o : out std_logic;

        start_button : in std_logic;
        busy_led     : out std_logic;
        done_led     : out std_logic
    );
end entity matrix_accelerator_full_top;

architecture rtl of matrix_accelerator_full_top is

    signal rx_valid : std_logic;
    signal rx_byte  : std_logic_vector(7 downto 0);

    signal tx_start : std_logic;
    signal tx_byte  : std_logic_vector(7 downto 0);
    signal tx_busy  : std_logic;

    signal protocol_start : std_logic;
    signal accel_start    : std_logic;
    signal accel_busy     : std_logic;
    signal accel_done     : std_logic;

    signal host_ready  : std_logic;
    signal host_rvalid : std_logic;
    signal host_rdata  : std_logic_vector(SDRAM_DATA_WIDTH-1 downto 0);

    signal perf_cycles       : unsigned(63 downto 0);
    signal perf_sdram_reads  : unsigned(63 downto 0);
    signal perf_sdram_writes : unsigned(63 downto 0);
    signal perf_mac_groups   : unsigned(63 downto 0);

begin

    busy_led <= accel_busy;
    done_led <= accel_done;

    accel_start <= start_button or protocol_start;

    u_uart_rx : entity work.uart_rx
        generic map (
            CLKS_PER_BIT => CLKS_PER_BIT
        )
        port map (
            clk       => clk,
            rst       => rst,
            rx_serial => uart_rx_i,
            rx_valid  => rx_valid,
            rx_byte   => rx_byte
        );

    u_uart_tx : entity work.uart_tx
        generic map (
            CLKS_PER_BIT => CLKS_PER_BIT
        )
        port map (
            clk       => clk,
            rst       => rst,
            tx_start  => tx_start,
            tx_byte   => tx_byte,
            tx_serial => uart_tx_o,
            tx_busy   => tx_busy
        );

    u_uart_protocol : entity work.uart_protocol
        port map (
            clk              => clk,
            rst              => rst,
            rx_valid         => rx_valid,
            rx_byte          => rx_byte,
            tx_busy          => tx_busy,
            tx_start         => tx_start,
            tx_byte          => tx_byte,
            accelerator_busy => accel_busy,
            accelerator_done => accel_done,
            start_pulse      => protocol_start
        );

    u_core : entity work.matrix_accelerator_sdram_core_top
        generic map (
            N                => N,
            TILE_SIZE        => TILE_SIZE,
            NUM_MACS         => NUM_MACS,
            DATA_WIDTH       => DATA_WIDTH,
            ACC_WIDTH        => ACC_WIDTH,
            SDRAM_DATA_WIDTH => SDRAM_DATA_WIDTH,
            SDRAM_ADDR_WIDTH => SDRAM_ADDR_WIDTH,
            USE_SIM_SDRAM    => true
        )
        port map (
            clk               => clk,
            rst               => rst,
            host_req          => '0',
            host_we           => '0',
            host_addr         => (others => '0'),
            host_wdata        => (others => '0'),
            host_byte_en      => (others => '1'),
            host_ready        => host_ready,
            host_rvalid       => host_rvalid,
            host_rdata        => host_rdata,
            start             => accel_start,
            busy              => accel_busy,
            done              => accel_done,
            perf_cycles       => perf_cycles,
            perf_sdram_reads  => perf_sdram_reads,
            perf_sdram_writes => perf_sdram_writes,
            perf_mac_groups   => perf_mac_groups
        );

end architecture rtl;
