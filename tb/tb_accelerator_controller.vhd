library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_accelerator_controller is
end entity tb_accelerator_controller;

architecture sim of tb_accelerator_controller is

    constant CLK_PERIOD       : time := 10 ns;
    constant N                : positive := 4;
    constant TILE_SIZE        : positive := 2;
    constant NUM_MACS         : positive := 2;
    constant DATA_WIDTH       : positive := 8;
    constant ACC_WIDTH        : positive := 32;
    constant SDRAM_DATA_WIDTH : positive := 32;
    constant SDRAM_ADDR_WIDTH : positive := 8;
    constant MATRIX_ELEMS     : natural := N * N;
    constant A_BASE           : natural := 0;
    constant B_BASE           : natural := MATRIX_ELEMS;
    constant C_BASE           : natural := MATRIX_ELEMS * 2;

    signal clk : std_logic := '0';
    signal rst : std_logic := '0';

    signal start : std_logic := '0';
    signal busy  : std_logic;
    signal done  : std_logic;

    signal ctrl_req     : std_logic;
    signal ctrl_we      : std_logic;
    signal ctrl_addr    : unsigned(SDRAM_ADDR_WIDTH-1 downto 0);
    signal ctrl_wdata   : std_logic_vector(SDRAM_DATA_WIDTH-1 downto 0);
    signal ctrl_byte_en : std_logic_vector((SDRAM_DATA_WIDTH/8)-1 downto 0);
    signal ctrl_ready   : std_logic;
    signal ctrl_rvalid  : std_logic;
    signal ctrl_rdata   : std_logic_vector(SDRAM_DATA_WIDTH-1 downto 0);

    signal host_req   : std_logic := '0';
    signal host_we    : std_logic := '0';
    signal host_addr  : unsigned(SDRAM_ADDR_WIDTH-1 downto 0) := (others => '0');
    signal host_wdata : std_logic_vector(SDRAM_DATA_WIDTH-1 downto 0) := (others => '0');
    signal host_rdata : std_logic_vector(SDRAM_DATA_WIDTH-1 downto 0);
    signal host_rvalid : std_logic;

    signal mem_req     : std_logic;
    signal mem_we      : std_logic;
    signal mem_addr    : unsigned(SDRAM_ADDR_WIDTH-1 downto 0);
    signal mem_wdata   : std_logic_vector(SDRAM_DATA_WIDTH-1 downto 0);
    signal mem_byte_en : std_logic_vector((SDRAM_DATA_WIDTH/8)-1 downto 0);
    signal mem_ready   : std_logic;
    signal mem_rvalid  : std_logic;
    signal mem_rdata   : std_logic_vector(SDRAM_DATA_WIDTH-1 downto 0);

    signal ctrl_active : std_logic;
    signal event_read  : std_logic;
    signal event_write : std_logic;
    signal event_mac   : std_logic;

    function a_value(row_idx : natural; col_idx : natural) return integer is
    begin
        return (row_idx + (2 * col_idx) + 1) mod 8;
    end function;

    function b_value(row_idx : natural; col_idx : natural) return integer is
    begin
        return ((3 * row_idx) + col_idx + 2) mod 8;
    end function;

    function c_expected(row_idx : natural; col_idx : natural) return integer is
        variable acc : integer := 0;
    begin
        for k in 0 to N-1 loop
            acc := acc + a_value(row_idx, k) * b_value(k, col_idx);
        end loop;

        return acc;
    end function;

begin

    clk <= not clk after CLK_PERIOD / 2;

    ctrl_active <= busy or start;

    mem_req     <= ctrl_req when ctrl_active = '1' else host_req;
    mem_we      <= ctrl_we when ctrl_active = '1' else host_we;
    mem_addr    <= ctrl_addr when ctrl_active = '1' else host_addr;
    mem_wdata   <= ctrl_wdata when ctrl_active = '1' else host_wdata;
    mem_byte_en <= ctrl_byte_en when ctrl_active = '1' else (others => '1');

    ctrl_ready  <= mem_ready when ctrl_active = '1' else '0';
    ctrl_rvalid <= mem_rvalid when ctrl_active = '1' else '0';
    ctrl_rdata  <= mem_rdata;
    host_rvalid <= mem_rvalid when ctrl_active = '0' else '0';
    host_rdata  <= mem_rdata;

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
            busy              => busy,
            done              => done,
            sdram_req         => ctrl_req,
            sdram_we          => ctrl_we,
            sdram_addr        => ctrl_addr,
            sdram_wdata       => ctrl_wdata,
            sdram_byte_en     => ctrl_byte_en,
            sdram_ready       => ctrl_ready,
            sdram_rvalid      => ctrl_rvalid,
            sdram_rdata       => ctrl_rdata,
            event_sdram_read  => event_read,
            event_sdram_write => event_write,
            event_mac_group   => event_mac
        );

    u_mem : entity work.sdram_model
        generic map (
            DATA_WIDTH => SDRAM_DATA_WIDTH,
            ADDR_WIDTH => SDRAM_ADDR_WIDTH,
            DEPTH      => 256
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

    stim_proc : process
        variable addr : natural;
        variable exec_cycles : natural := 0;
    begin
        rst <= '1';
        wait for 3 * CLK_PERIOD;
        rst <= '0';
        wait until rising_edge(clk);

        for row_idx in 0 to N-1 loop
            for col_idx in 0 to N-1 loop
                addr := row_idx * N + col_idx;
                host_addr  <= to_unsigned(A_BASE + addr, SDRAM_ADDR_WIDTH);
                host_wdata <= std_logic_vector(to_signed(a_value(row_idx, col_idx), SDRAM_DATA_WIDTH));
                host_we    <= '1';
                host_req   <= '1';
                wait until rising_edge(clk);
                host_req <= '0';
                host_we  <= '0';
                wait until rising_edge(clk);

                host_addr  <= to_unsigned(B_BASE + addr, SDRAM_ADDR_WIDTH);
                host_wdata <= std_logic_vector(to_signed(b_value(row_idx, col_idx), SDRAM_DATA_WIDTH));
                host_we    <= '1';
                host_req   <= '1';
                wait until rising_edge(clk);
                host_req <= '0';
                host_we  <= '0';
                wait until rising_edge(clk);
            end loop;
        end loop;

        start <= '1';
        wait until rising_edge(clk);
        start <= '0';

        for cycle_idx in 0 to 5000 loop
            wait until rising_edge(clk);
            exec_cycles := exec_cycles + 1;
            exit when done = '1';
        end loop;

        assert done = '1'
            report "accelerator_controller nao finalizou."
            severity failure;

        report "Ciclos de execucao: " & integer'image(exec_cycles) severity note;

        for row_idx in 0 to N-1 loop
            for col_idx in 0 to N-1 loop
                addr := row_idx * N + col_idx;
                host_addr <= to_unsigned(C_BASE + addr, SDRAM_ADDR_WIDTH);
                host_we   <= '0';
                host_req  <= '1';
                wait until rising_edge(clk);
                host_req <= '0';
                wait for 1 ns;

                assert host_rvalid = '1' and signed(host_rdata) = to_signed(c_expected(row_idx, col_idx), SDRAM_DATA_WIDTH)
                    report "Resultado incorreto no accelerator_controller."
                    severity failure;
            end loop;
        end loop;

        report "SIM_RESULT: PASS" severity note;
        finish;
    end process;

end architecture sim;
