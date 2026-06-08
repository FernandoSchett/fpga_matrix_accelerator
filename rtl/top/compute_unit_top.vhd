library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity compute_unit_top is
    generic (
        TILE_SIZE           : positive := 4;
        NUM_MACS            : positive := 4;
        DATA_WIDTH          : positive := 8;
        ACC_WIDTH           : positive := 32;
        MAC_PIPELINE_STAGES : natural := 0
    );
    port (
        clk : in std_logic;
        rst : in std_logic;

        start : in std_logic;
        busy  : out std_logic;
        done  : out std_logic;

        result_probe   : out std_logic_vector(31 downto 0);
        mac_ops_issued : out unsigned(31 downto 0)
    );
end entity compute_unit_top;

architecture rtl of compute_unit_top is

    constant TILE_ELEMS  : positive := TILE_SIZE * TILE_SIZE;
    constant A_TILE_BITS : positive := TILE_ELEMS * DATA_WIDTH;
    constant C_TILE_BITS : positive := TILE_ELEMS * ACC_WIDTH;

    signal seed_counter  : unsigned(31 downto 0) := x"1ACEB00C";
    signal running       : std_logic := '0';
    signal core_start    : std_logic := '0';
    signal core_done     : std_logic := '0';

    signal a_tile_reg      : std_logic_vector(A_TILE_BITS-1 downto 0) := (others => '0');
    signal b_tile_reg      : std_logic_vector(A_TILE_BITS-1 downto 0) := (others => '0');
    signal c_tile_in_reg   : std_logic_vector(C_TILE_BITS-1 downto 0) := (others => '0');
    signal c_tile_out      : std_logic_vector(C_TILE_BITS-1 downto 0);

    function make_pattern(
        constant seed  : unsigned;
        constant width : positive;
        constant salt  : natural
    ) return std_logic_vector is
        variable result   : std_logic_vector(width-1 downto 0);
        variable seed_idx : natural;
    begin
        for bit_idx in 0 to width-1 loop
            seed_idx := (bit_idx + salt) mod seed'length;
            result(bit_idx) := seed(seed_idx);
            if ((bit_idx + salt) mod 7) = 0 then
                result(bit_idx) := not result(bit_idx);
            end if;
        end loop;

        return result;
    end function;

    function xor_probe(constant flat : std_logic_vector) return std_logic_vector is
        variable result : std_logic_vector(31 downto 0) := (others => '0');
    begin
        for bit_idx in 0 to flat'length-1 loop
            result(bit_idx mod 32) := result(bit_idx mod 32) xor flat(bit_idx);
        end loop;

        return result;
    end function;

begin

    core_start <= start and not running;
    busy       <= running;
    done       <= core_done;

    result_probe <= xor_probe(c_tile_out);

    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                seed_counter  <= x"1ACEB00C";
                running       <= '0';
                a_tile_reg    <= (others => '0');
                b_tile_reg    <= (others => '0');
                c_tile_in_reg <= (others => '0');
            else
                if running = '0' then
                    seed_counter <= seed_counter + 1;
                end if;

                if core_start = '1' then
                    a_tile_reg    <= make_pattern(seed_counter, A_TILE_BITS, 1);
                    b_tile_reg    <= make_pattern(seed_counter, A_TILE_BITS, 11);
                    c_tile_in_reg <= make_pattern(seed_counter, C_TILE_BITS, 23);
                    seed_counter  <= seed_counter + x"00010001";
                    running       <= '1';
                elsif core_done = '1' then
                    running <= '0';
                end if;
            end if;
        end if;
    end process;

    u_compute : entity work.matrix_tiled_compute_core
        generic map (
            TILE_SIZE           => TILE_SIZE,
            NUM_MACS            => NUM_MACS,
            DATA_WIDTH          => DATA_WIDTH,
            ACC_WIDTH           => ACC_WIDTH,
            MAC_PIPELINE_STAGES => MAC_PIPELINE_STAGES
        )
        port map (
            clk            => clk,
            rst            => rst,
            start          => core_start,
            done           => core_done,
            a_tile         => a_tile_reg,
            b_tile         => b_tile_reg,
            c_tile_in      => c_tile_in_reg,
            c_tile_out     => c_tile_out,
            mac_ops_issued => mac_ops_issued
        );

end architecture rtl;
