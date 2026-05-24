library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.matrix_tiled_pkg.all;

entity tile_buffer_m10k is
    generic (
        TILE_SIZE     : positive := 4;
        DATA_WIDTH    : positive := 8;
        ACC_WIDTH     : positive := 32;
        USE_M10K      : boolean  := true;
        IS_ACC_BUFFER : boolean  := false;
        BUFFER_IMPL   : string   := "INFERRED"
    );
    port (
        clk : in std_logic;
        rst : in std_logic;

        wr_en : in std_logic;

        local_row : in unsigned(clog2(TILE_SIZE)-1 downto 0);
        local_col : in unsigned(clog2(TILE_SIZE)-1 downto 0);

        wr_data : in signed((DATA_WIDTH + (boolean'pos(IS_ACC_BUFFER) * (ACC_WIDTH - DATA_WIDTH)))-1 downto 0);
        rd_data : out signed((DATA_WIDTH + (boolean'pos(IS_ACC_BUFFER) * (ACC_WIDTH - DATA_WIDTH)))-1 downto 0);

        local_addr_dbg : out unsigned(clog2(TILE_SIZE*TILE_SIZE)-1 downto 0)
    );
end entity tile_buffer_m10k;

architecture rtl of tile_buffer_m10k is

    constant TILE_ELEMS   : positive := TILE_SIZE * TILE_SIZE;
    constant ADDR_WIDTH   : positive := clog2(TILE_ELEMS);
    constant BUFFER_WIDTH : positive := DATA_WIDTH + (boolean'pos(IS_ACC_BUFFER) * (ACC_WIDTH - DATA_WIDTH));

    subtype word_t is std_logic_vector(BUFFER_WIDTH-1 downto 0);
    type ram_t is array (0 to TILE_ELEMS-1) of word_t;

    function local_addr_from_row_col(
        constant row_v : unsigned;
        constant col_v : unsigned
    ) return unsigned is
        variable addr_nat : natural;
    begin
        addr_nat := (to_integer(row_v) * TILE_SIZE) + to_integer(col_v);
        return to_unsigned(addr_nat, ADDR_WIDTH);
    end function;

    signal local_addr : unsigned(ADDR_WIDTH-1 downto 0);

begin

    assert TILE_SIZE > 1
        report "tile_buffer_m10k exige TILE_SIZE maior que 1."
        severity failure;

    assert ACC_WIDTH >= DATA_WIDTH
        report "tile_buffer_m10k exige ACC_WIDTH >= DATA_WIDTH."
        severity failure;

    assert BUFFER_IMPL = "INFERRED" or BUFFER_IMPL = "IP"
        report "BUFFER_IMPL deve ser INFERRED ou IP."
        severity failure;

    local_addr <= local_addr_from_row_col(local_row, local_col);
    local_addr_dbg <= local_addr;

    gen_inferred_m10k : if BUFFER_IMPL = "INFERRED" and USE_M10K generate
        signal ram    : ram_t := (others => (others => '0'));
        signal rd_reg : word_t := (others => '0');

        attribute ramstyle : string;
        attribute ramstyle of ram : signal is "M10K";
    begin
        process(clk, rst)
            variable addr_int : integer;
        begin
            if rst = '1' then
                rd_reg <= (others => '0');

            elsif rising_edge(clk) then
                addr_int := to_integer(local_addr);

                if wr_en = '1' and addr_int < TILE_ELEMS then
                    ram(addr_int) <= std_logic_vector(wr_data);
                end if;

                if addr_int < TILE_ELEMS then
                    rd_reg <= ram(addr_int);
                else
                    rd_reg <= (others => '0');
                end if;
            end if;
        end process;

        rd_data <= signed(rd_reg);
    end generate;

    gen_inferred_logic : if BUFFER_IMPL = "INFERRED" and not USE_M10K generate
        signal ram    : ram_t := (others => (others => '0'));
        signal rd_reg : word_t := (others => '0');

        attribute ramstyle : string;
        attribute ramstyle of ram : signal is "logic";
    begin
        process(clk, rst)
            variable addr_int : integer;
        begin
            if rst = '1' then
                rd_reg <= (others => '0');

            elsif rising_edge(clk) then
                addr_int := to_integer(local_addr);

                if wr_en = '1' and addr_int < TILE_ELEMS then
                    ram(addr_int) <= std_logic_vector(wr_data);
                end if;

                if addr_int < TILE_ELEMS then
                    rd_reg <= ram(addr_int);
                else
                    rd_reg <= (others => '0');
                end if;
            end if;
        end process;

        rd_data <= signed(rd_reg);
    end generate;

    gen_ip_stub : if BUFFER_IMPL = "IP" generate
        signal ram    : ram_t := (others => (others => '0'));
        signal rd_reg : word_t := (others => '0');
    begin
        -- Stub sintetizavel para trocar futuramente por On-Chip Memory/RAM IP
        -- do Quartus. Mantenha esta entity estavel e substitua somente este
        -- generate pelo componente gerado no Platform Designer/IP Catalog.
        process(clk, rst)
            variable addr_int : integer;
        begin
            if rst = '1' then
                rd_reg <= (others => '0');

            elsif rising_edge(clk) then
                addr_int := to_integer(local_addr);

                if wr_en = '1' and addr_int < TILE_ELEMS then
                    ram(addr_int) <= std_logic_vector(wr_data);
                end if;

                if addr_int < TILE_ELEMS then
                    rd_reg <= ram(addr_int);
                else
                    rd_reg <= (others => '0');
                end if;
            end if;
        end process;

        rd_data <= signed(rd_reg);
    end generate;

end architecture rtl;
