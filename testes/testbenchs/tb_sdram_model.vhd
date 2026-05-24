library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_sdram_model is
end entity tb_sdram_model;

architecture sim of tb_sdram_model is

    constant CLK_PERIOD   : time := 10 ns;
    constant DATA_WIDTH   : positive := 32;
    constant ADDR_WIDTH   : positive := 8;
    constant READ_LATENCY : natural := 3;
    constant WRITE_LATENCY : natural := 2;

    signal clk : std_logic := '0';
    signal rst : std_logic := '0';

    signal rd_req   : std_logic := '0';
    signal rd_addr  : unsigned(ADDR_WIDTH-1 downto 0) := (others => '0');
    signal rd_data  : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal rd_valid : std_logic;
    signal rd_ready : std_logic;

    signal wr_req   : std_logic := '0';
    signal wr_addr  : unsigned(ADDR_WIDTH-1 downto 0) := (others => '0');
    signal wr_data  : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');
    signal wr_ready : std_logic;

    signal busy : std_logic;

begin

    clk <= not clk after CLK_PERIOD / 2;

    dut : entity work.sdram_model
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
            rd_req   => rd_req,
            rd_addr  => rd_addr,
            rd_data  => rd_data,
            rd_valid => rd_valid,
            rd_ready => rd_ready,
            wr_req   => wr_req,
            wr_addr  => wr_addr,
            wr_data  => wr_data,
            wr_ready => wr_ready,
            busy     => busy
        );

    stim_proc : process
    begin
        rst <= '1';
        wait for 3 * CLK_PERIOD;
        rst <= '0';
        wait until rising_edge(clk);
        wait for 1 ns;

        assert rd_ready = '1' and wr_ready = '1' and busy = '0' and rd_valid = '0'
            report "Estado inicial da interface SDRAM incorreto."
            severity failure;

        wr_addr <= to_unsigned(7, ADDR_WIDTH);
        wr_data <= x"12345678";
        wr_req  <= '1';
        wait until rising_edge(clk);
        wr_req <= '0';
        wait for 1 ns;

        assert wr_ready = '0' and rd_ready = '0' and busy = '1'
            report "Modelo nao entrou em busy apos aceitar escrita."
            severity failure;

        for cycle_idx in 1 to WRITE_LATENCY-1 loop
            wait until rising_edge(clk);
            wait for 1 ns;

            assert wr_ready = '0' and busy = '1'
                report "wr_ready voltou antes da latencia de escrita."
                severity failure;
        end loop;

        wait until rising_edge(clk);
        wait for 1 ns;

        assert wr_ready = '1' and rd_ready = '1' and busy = '0'
            report "wr_ready nao voltou apos WRITE_LATENCY."
            severity failure;

        rd_addr <= to_unsigned(7, ADDR_WIDTH);
        rd_req  <= '1';
        wait until rising_edge(clk);
        rd_req <= '0';
        wait for 1 ns;

        assert rd_ready = '0' and wr_ready = '0' and busy = '1' and rd_valid = '0'
            report "Modelo nao entrou em busy apos aceitar leitura."
            severity failure;

        for cycle_idx in 1 to READ_LATENCY-1 loop
            wait until rising_edge(clk);
            wait for 1 ns;

            assert rd_valid = '0' and rd_ready = '0' and busy = '1'
                report "rd_valid ocorreu antes da latencia de leitura."
                severity failure;
        end loop;

        wait until rising_edge(clk);
        wait for 1 ns;

        assert rd_valid = '1'
            report "rd_valid nao foi gerado apos READ_LATENCY."
            severity failure;

        assert rd_data = x"12345678"
            report "sdram_model retornou dado incorreto."
            severity failure;

        assert rd_ready = '1' and wr_ready = '1' and busy = '0'
            report "Interface nao voltou para idle apos leitura."
            severity failure;

        wait until rising_edge(clk);
        wait for 1 ns;

        assert rd_valid = '0'
            report "rd_valid deveria ser pulso de um ciclo."
            severity failure;

        report "SIM_RESULT: PASS" severity note;
        finish;
    end process;

end architecture sim;
