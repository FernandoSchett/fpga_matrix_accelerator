library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.matrix_tiled_pkg.all;
use work.matrix_accel_config_pkg.all;

entity matrix_memory_map is
    generic (
        N          : positive := DEFAULT_N;
        DATA_WIDTH : positive := DEFAULT_DATA_WIDTH;
        ACC_WIDTH  : positive := DEFAULT_ACC_WIDTH;
        ADDR_WIDTH : positive := DEFAULT_SDRAM_ADDR_WIDTH
    );
    port (
        matrix_id : in std_logic_vector(1 downto 0);
        row_idx   : in unsigned(clog2(N)-1 downto 0);
        col_idx   : in unsigned(clog2(N)-1 downto 0);
        addr      : out unsigned(ADDR_WIDTH-1 downto 0)
    );
end entity matrix_memory_map;

architecture rtl of matrix_memory_map is

    -- Enderecos logicos por elemento:
    --   A[row][col] -> BASE_A + row * N + col
    --   B[row][col] -> BASE_B + row * N + col
    --   C[row][col] -> BASE_C + row * N + col
    --
    -- Nesta etapa, A/B e C ocupam espacos logicos separados na SDRAM.
    -- A e B usam DATA_WIDTH bits validos da palavra armazenada.
    -- C usa ACC_WIDTH bits validos da palavra armazenada.
    --
    -- Packing fisico por byte/palavra do controlador SDRAM real deve ficar
    -- escondido no wrapper de memoria, nao no scheduler nem no compute.
    constant MATRIX_ELEMS : natural := N * N;

    constant BASE_A : natural := 0;
    constant BASE_B : natural := MATRIX_ELEMS;
    constant BASE_C : natural := MATRIX_ELEMS * 2;

begin

    assert DATA_WIDTH <= ACC_WIDTH
        report "matrix_memory_map assume ACC_WIDTH >= DATA_WIDTH."
        severity failure;

    process(matrix_id, row_idx, col_idx)
        variable base        : natural;
        variable element_idx : natural;
    begin
        if matrix_id = MATRIX_ID_A then
            base := BASE_A;
        elsif matrix_id = MATRIX_ID_B then
            base := BASE_B;
        elsif matrix_id = MATRIX_ID_C then
            base := BASE_C;
        else
            base := BASE_C;
        end if;

        element_idx := row_major_addr(to_integer(row_idx), to_integer(col_idx), N);
        addr <= to_unsigned(base + element_idx, ADDR_WIDTH);
    end process;

end architecture rtl;
