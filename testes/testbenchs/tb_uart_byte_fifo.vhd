library ieee;
use ieee.std_logic_1164.all;
use std.env.all;

entity tb_uart_byte_fifo is
end entity tb_uart_byte_fifo;

architecture sim of tb_uart_byte_fifo is

    constant CLK_PERIOD : time := 10 ns;

    signal clk : std_logic := '0';
    signal rst : std_logic := '0';

    signal wr_en   : std_logic := '0';
    signal wr_data : std_logic_vector(7 downto 0) := (others => '0');
    signal rd_en   : std_logic := '0';
    signal rd_data : std_logic_vector(7 downto 0);
    signal empty   : std_logic;
    signal full    : std_logic;
    signal almost_full : std_logic;
    signal overflow    : std_logic;
    signal underflow   : std_logic;

    procedure push_byte(
        signal wr_en_sig   : out std_logic;
        signal wr_data_sig : out std_logic_vector(7 downto 0);
        constant value     : std_logic_vector(7 downto 0)
    ) is
    begin
        wr_data_sig <= value;
        wr_en_sig   <= '1';
        wait until rising_edge(clk);
        wait for 1 ns;
        wr_en_sig   <= '0';
        wait until rising_edge(clk);
        wait for 1 ns;
    end procedure;

    procedure pop_expect(
        signal rd_en_sig   : out std_logic;
        signal rd_data_sig : in std_logic_vector(7 downto 0);
        constant expected  : std_logic_vector(7 downto 0)
    ) is
    begin
        assert rd_data_sig = expected
            report "FIFO retornou byte fora de ordem."
            severity failure;

        rd_en_sig <= '1';
        wait until rising_edge(clk);
        wait for 1 ns;
        rd_en_sig <= '0';
        wait until rising_edge(clk);
        wait for 1 ns;
    end procedure;

begin

    clk <= not clk after CLK_PERIOD / 2;

    dut : entity work.uart_byte_fifo
        generic map (
            FIFO_DEPTH        => 4,
            ALMOST_FULL_LEVEL => 3,
            RAM_BLOCK_TYPE    => "M10K"
        )
        port map (
            clk         => clk,
            rst         => rst,
            wr_en       => wr_en,
            wr_data     => wr_data,
            rd_en       => rd_en,
            rd_data     => rd_data,
            empty       => empty,
            full        => full,
            almost_full => almost_full,
            overflow    => overflow,
            underflow   => underflow
        );

    stim_proc : process
    begin
        rst <= '1';
        wait for 3 * CLK_PERIOD;
        rst <= '0';
        wait until rising_edge(clk);
        wait for 1 ns;

        assert empty = '1' report "FIFO deveria iniciar vazio." severity failure;
        assert overflow = '0' and underflow = '0'
            report "Flags de erro deveriam iniciar limpas."
            severity failure;

        push_byte(wr_en, wr_data, x"11");
        assert empty = '0' report "FIFO nao saiu de empty apos escrita." severity failure;
        assert rd_data = x"11" report "Show-ahead nao mostrou primeiro byte." severity failure;

        push_byte(wr_en, wr_data, x"22");
        push_byte(wr_en, wr_data, x"33");
        assert almost_full = '1'
            report "almost_full deveria subir no terceiro byte."
            severity failure;

        push_byte(wr_en, wr_data, x"44");
        assert full = '1' report "FIFO deveria ficar cheio." severity failure;

        push_byte(wr_en, wr_data, x"55");
        assert overflow = '1'
            report "Overflow deveria ser latched ao escrever com FIFO cheio."
            severity failure;

        pop_expect(rd_en, rd_data, x"11");
        pop_expect(rd_en, rd_data, x"22");
        pop_expect(rd_en, rd_data, x"33");
        pop_expect(rd_en, rd_data, x"44");

        assert empty = '1' report "FIFO deveria ficar vazio apos quatro leituras." severity failure;

        rd_en <= '1';
        wait until rising_edge(clk);
        wait for 1 ns;
        rd_en <= '0';
        assert underflow = '1'
            report "Underflow deveria ser latched ao ler FIFO vazio."
            severity failure;

        report "SIM_RESULT: PASS" severity note;
        finish;
    end process;

end architecture sim;
