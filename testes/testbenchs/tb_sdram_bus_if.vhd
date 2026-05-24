library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_sdram_bus_if is
end entity tb_sdram_bus_if;

architecture sim of tb_sdram_bus_if is

    constant CLK_PERIOD    : time := 10 ns;
    constant DATA_WIDTH    : positive := 32;
    constant ADDR_WIDTH    : positive := 8;
    constant READ_LATENCY  : natural := 2;
    constant WRITE_LATENCY : natural := 1;

    signal clk : std_logic := '0';
    signal rst : std_logic := '0';

    signal client_rd_req   : std_logic := '0';
    signal client_rd_addr  : unsigned(ADDR_WIDTH-1 downto 0) := (others => '0');
    signal client_rd_data  : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal client_rd_valid : std_logic;
    signal client_rd_ready : std_logic;
    signal client_wr_req   : std_logic := '0';
    signal client_wr_addr  : unsigned(ADDR_WIDTH-1 downto 0) := (others => '0');
    signal client_wr_data  : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');
    signal client_wr_ready : std_logic;
    signal client_busy     : std_logic;

    signal mem_rd_req   : std_logic;
    signal mem_rd_addr  : unsigned(ADDR_WIDTH-1 downto 0);
    signal mem_rd_data  : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal mem_rd_valid : std_logic;
    signal mem_rd_ready : std_logic;
    signal mem_wr_req   : std_logic;
    signal mem_wr_addr  : unsigned(ADDR_WIDTH-1 downto 0);
    signal mem_wr_data  : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal mem_wr_ready : std_logic;
    signal mem_busy     : std_logic;

begin

    clk <= not clk after CLK_PERIOD / 2;

    u_bus : entity work.sdram_bus_if
        generic map (
            DATA_WIDTH    => DATA_WIDTH,
            ADDR_WIDTH    => ADDR_WIDTH,
            READ_LATENCY  => READ_LATENCY,
            WRITE_LATENCY => WRITE_LATENCY
        )
        port map (
            clk             => clk,
            rst             => rst,
            client_rd_req   => client_rd_req,
            client_rd_addr  => client_rd_addr,
            client_rd_data  => client_rd_data,
            client_rd_valid => client_rd_valid,
            client_rd_ready => client_rd_ready,
            client_wr_req   => client_wr_req,
            client_wr_addr  => client_wr_addr,
            client_wr_data  => client_wr_data,
            client_wr_ready => client_wr_ready,
            client_busy     => client_busy,
            mem_rd_req      => mem_rd_req,
            mem_rd_addr     => mem_rd_addr,
            mem_rd_data     => mem_rd_data,
            mem_rd_valid    => mem_rd_valid,
            mem_rd_ready    => mem_rd_ready,
            mem_wr_req      => mem_wr_req,
            mem_wr_addr     => mem_wr_addr,
            mem_wr_data     => mem_wr_data,
            mem_wr_ready    => mem_wr_ready,
            mem_busy        => mem_busy
        );

    u_mem : entity work.sdram_model
        generic map (
            DATA_WIDTH    => DATA_WIDTH,
            ADDR_WIDTH    => ADDR_WIDTH,
            READ_LATENCY  => READ_LATENCY,
            WRITE_LATENCY => WRITE_LATENCY,
            DEPTH         => 256
        )
        port map (
            clk      => clk,
            rst      => rst,
            rd_req   => mem_rd_req,
            rd_addr  => mem_rd_addr,
            rd_data  => mem_rd_data,
            rd_valid => mem_rd_valid,
            rd_ready => mem_rd_ready,
            wr_req   => mem_wr_req,
            wr_addr  => mem_wr_addr,
            wr_data  => mem_wr_data,
            wr_ready => mem_wr_ready,
            busy     => mem_busy
        );

    stim_proc : process
    begin
        rst <= '1';
        wait for 3 * CLK_PERIOD;
        rst <= '0';
        wait until rising_edge(clk);

        client_wr_addr <= to_unsigned(5, ADDR_WIDTH);
        client_wr_data <= x"CAFEBABE";
        client_wr_req  <= '1';
        wait until rising_edge(clk);
        client_wr_req <= '0';

        for idx in 1 to WRITE_LATENCY loop
            wait until rising_edge(clk);
        end loop;

        client_rd_addr <= to_unsigned(5, ADDR_WIDTH);
        client_rd_req  <= '1';
        wait until rising_edge(clk);
        client_rd_req <= '0';

        for idx in 1 to READ_LATENCY loop
            wait until rising_edge(clk);
        end loop;

        wait for 1 ns;

        assert client_rd_valid = '1' and client_rd_data = x"CAFEBABE"
            report "sdram_bus_if falhou no pass-through da interface nova."
            severity failure;

        report "SIM_RESULT: PASS" severity note;
        finish;
    end process;

end architecture sim;
