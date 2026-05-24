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
        SDRAM_DEPTH      : positive := 262144;
        READ_LATENCY     : natural  := 3;
        WRITE_LATENCY    : natural  := 2;
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

    signal cmd_start   : std_logic;
    signal accel_start : std_logic;
    signal accel_busy  : std_logic;
    signal accel_done  : std_logic;
    signal done_seen   : std_logic := '0';

    signal host_wr_en      : std_logic;
    signal host_matrix_sel : std_logic_vector(1 downto 0);
    signal host_addr       : unsigned(SDRAM_ADDR_WIDTH-1 downto 0);
    signal host_data_in    : std_logic_vector(SDRAM_DATA_WIDTH-1 downto 0);
    signal host_rd_en      : std_logic;
    signal host_rd_addr    : unsigned(SDRAM_ADDR_WIDTH-1 downto 0);
    signal host_data_out   : std_logic_vector(SDRAM_DATA_WIDTH-1 downto 0);

    signal perf_total_cycles        : unsigned(63 downto 0);
    signal perf_load_cycles         : unsigned(63 downto 0);
    signal perf_compute_cycles      : unsigned(63 downto 0);
    signal perf_store_cycles        : unsigned(63 downto 0);
    signal perf_num_tiles_processed : unsigned(63 downto 0);
    signal perf_num_mac_ops_issued  : unsigned(63 downto 0);

begin

    busy_led <= accel_busy;
    done_led <= done_seen;

    accel_start <= start_button or cmd_start;

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

    u_command : entity work.command_interface
        generic map (
            ADDR_WIDTH        => SDRAM_ADDR_WIDTH,
            DATA_WIDTH        => SDRAM_DATA_WIDTH,
            COUNTER_WIDTH     => 64,
            HOST_READ_LATENCY => READ_LATENCY + 2
        )
        port map (
            clk                      => clk,
            rst                      => rst,
            rx_valid                 => rx_valid,
            rx_byte                  => rx_byte,
            tx_busy                  => tx_busy,
            tx_start                 => tx_start,
            tx_byte                  => tx_byte,
            accelerator_busy         => accel_busy,
            accelerator_done         => done_seen,
            host_wr_en               => host_wr_en,
            host_matrix_sel          => host_matrix_sel,
            host_addr                => host_addr,
            host_data_in             => host_data_in,
            host_rd_en               => host_rd_en,
            host_rd_addr             => host_rd_addr,
            host_data_out            => host_data_out,
            start                    => cmd_start,
            perf_total_cycles        => perf_total_cycles,
            perf_load_cycles         => perf_load_cycles,
            perf_compute_cycles      => perf_compute_cycles,
            perf_store_cycles        => perf_store_cycles,
            perf_num_tiles_processed => perf_num_tiles_processed,
            perf_num_mac_ops_issued  => perf_num_mac_ops_issued
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
            SDRAM_DEPTH      => SDRAM_DEPTH,
            READ_LATENCY     => READ_LATENCY,
            WRITE_LATENCY    => WRITE_LATENCY
        )
        port map (
            clk                      => clk,
            rst                      => rst,
            host_wr_en               => host_wr_en,
            host_matrix_sel          => host_matrix_sel,
            host_addr                => host_addr,
            host_data_in             => host_data_in,
            host_rd_en               => host_rd_en,
            host_rd_addr             => host_rd_addr,
            host_data_out            => host_data_out,
            start                    => accel_start,
            busy                     => accel_busy,
            done                     => accel_done,
            perf_total_cycles        => perf_total_cycles,
            perf_load_cycles         => perf_load_cycles,
            perf_compute_cycles      => perf_compute_cycles,
            perf_store_cycles        => perf_store_cycles,
            perf_num_tiles_processed => perf_num_tiles_processed,
            perf_num_mac_ops_issued  => perf_num_mac_ops_issued
        );

    process(clk, rst)
    begin
        if rst = '1' then
            done_seen <= '0';
        elsif rising_edge(clk) then
            if accel_start = '1' then
                done_seen <= '0';
            elsif accel_done = '1' then
                done_seen <= '1';
            end if;
        end if;
    end process;

end architecture rtl;
