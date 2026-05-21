library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity matrix_mult_core is
    generic (
        DATA_WIDTH : integer := 16;
        ACC_WIDTH  : integer := 32
    );
    port (
        clk   : in std_logic;
        rst   : in std_logic;
        start : in std_logic;
        done  : out std_logic;

        a00 : in signed(DATA_WIDTH-1 downto 0);
        a01 : in signed(DATA_WIDTH-1 downto 0);
        a10 : in signed(DATA_WIDTH-1 downto 0);
        a11 : in signed(DATA_WIDTH-1 downto 0);

        b00 : in signed(DATA_WIDTH-1 downto 0);
        b01 : in signed(DATA_WIDTH-1 downto 0);
        b10 : in signed(DATA_WIDTH-1 downto 0);
        b11 : in signed(DATA_WIDTH-1 downto 0);

        c00_in : in signed(ACC_WIDTH-1 downto 0);
        c01_in : in signed(ACC_WIDTH-1 downto 0);
        c10_in : in signed(ACC_WIDTH-1 downto 0);
        c11_in : in signed(ACC_WIDTH-1 downto 0);

        c00 : out signed(ACC_WIDTH-1 downto 0);
        c01 : out signed(ACC_WIDTH-1 downto 0);
        c10 : out signed(ACC_WIDTH-1 downto 0);
        c11 : out signed(ACC_WIDTH-1 downto 0)
    );
end entity matrix_mult_core;

architecture rtl of matrix_mult_core is

    type state_t is (
        IDLE,
        COMPUTE,
        WRITE_RESULT,
        DONE_STATE
    );

    signal state : state_t := IDLE;

    signal i_idx : integer range 0 to 1 := 0;
    signal j_idx : integer range 0 to 1 := 0;
    signal k_idx : integer range 0 to 1 := 0;

    signal acc_reg    : signed(ACC_WIDTH-1 downto 0) := (others => '0');
    signal mac_a      : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal mac_b      : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal mac_result : signed(ACC_WIDTH-1 downto 0);

    signal c00_base_reg : signed(ACC_WIDTH-1 downto 0) := (others => '0');
    signal c01_base_reg : signed(ACC_WIDTH-1 downto 0) := (others => '0');
    signal c10_base_reg : signed(ACC_WIDTH-1 downto 0) := (others => '0');
    signal c11_base_reg : signed(ACC_WIDTH-1 downto 0) := (others => '0');

    signal c00_reg : signed(ACC_WIDTH-1 downto 0) := (others => '0');
    signal c01_reg : signed(ACC_WIDTH-1 downto 0) := (others => '0');
    signal c10_reg : signed(ACC_WIDTH-1 downto 0) := (others => '0');
    signal c11_reg : signed(ACC_WIDTH-1 downto 0) := (others => '0');

    signal done_reg : std_logic := '0';

    -- Tenta impedir o Quartus de achatar a instância do MAC.
    -- Assim o u_mac tem mais chance de aparecer como bloco separado no RTL Viewer.
    attribute keep_hierarchy : string;
    attribute preserve_hierarchical_boundary : string;
    attribute altera_attribute : string;

    attribute keep_hierarchy of u_mac : label is "true";
    attribute preserve_hierarchical_boundary of u_mac : label is "true";
    attribute altera_attribute of u_mac : label is "-name PRESERVE_HIERARCHICAL_BOUNDARY ON";

begin

    done <= done_reg;

    c00 <= c00_reg;
    c01 <= c01_reg;
    c10 <= c10_reg;
    c11 <= c11_reg;

    -- Seleciona A(i,k)
    process(i_idx, k_idx, a00, a01, a10, a11)
    begin
        if i_idx = 0 then
            if k_idx = 0 then
                mac_a <= a00;
            else
                mac_a <= a01;
            end if;
        else
            if k_idx = 0 then
                mac_a <= a10;
            else
                mac_a <= a11;
            end if;
        end if;
    end process;

    -- Seleciona B(k,j)
    process(k_idx, j_idx, b00, b01, b10, b11)
    begin
        if k_idx = 0 then
            if j_idx = 0 then
                mac_b <= b00;
            else
                mac_b <= b01;
            end if;
        else
            if j_idx = 0 then
                mac_b <= b10;
            else
                mac_b <= b11;
            end if;
        end if;
    end process;

    -- Bloco MAC instanciado explicitamente.
    -- Este é o bloco que você quer ver como "caixinha" na hierarquia.
    u_mac : entity work.mac_unit
        generic map (
            DATA_WIDTH => DATA_WIDTH,
            ACC_WIDTH  => ACC_WIDTH
        )
        port map (
            a       => mac_a,
            b       => mac_b,
            acc_in  => acc_reg,
            acc_out => mac_result
        );

    process(clk, rst)
    begin
        if rst = '1' then
            state    <= IDLE;
            i_idx    <= 0;
            j_idx    <= 0;
            k_idx    <= 0;
            acc_reg  <= (others => '0');

            c00_base_reg <= (others => '0');
            c01_base_reg <= (others => '0');
            c10_base_reg <= (others => '0');
            c11_base_reg <= (others => '0');

            c00_reg  <= (others => '0');
            c01_reg  <= (others => '0');
            c10_reg  <= (others => '0');
            c11_reg  <= (others => '0');
            done_reg <= '0';

        elsif rising_edge(clk) then

            case state is

                when IDLE =>
                    done_reg <= '0';
                    acc_reg  <= (others => '0');
                    i_idx    <= 0;
                    j_idx    <= 0;
                    k_idx    <= 0;

                    if start = '1' then
                        c00_base_reg <= c00_in;
                        c01_base_reg <= c01_in;
                        c10_base_reg <= c10_in;
                        c11_base_reg <= c11_in;

                        state <= COMPUTE;
                    end if;

                when COMPUTE =>
                    acc_reg <= mac_result;

                    if k_idx = 0 then
                        k_idx <= 1;
                    else
                        state <= WRITE_RESULT;
                    end if;

                when WRITE_RESULT =>
                    if i_idx = 0 and j_idx = 0 then
                        c00_reg <= c00_base_reg + acc_reg;
                    elsif i_idx = 0 and j_idx = 1 then
                        c01_reg <= c01_base_reg + acc_reg;
                    elsif i_idx = 1 and j_idx = 0 then
                        c10_reg <= c10_base_reg + acc_reg;
                    else
                        c11_reg <= c11_base_reg + acc_reg;
                    end if;

                    acc_reg <= (others => '0');
                    k_idx   <= 0;

                    if i_idx = 1 and j_idx = 1 then
                        state <= DONE_STATE;
                    else
                        if j_idx = 0 then
                            j_idx <= 1;
                        else
                            j_idx <= 0;
                            i_idx <= 1;
                        end if;

                        state <= COMPUTE;
                    end if;

                when DONE_STATE =>
                    done_reg <= '1';

                    if start = '0' then
                        state <= IDLE;
                    end if;

            end case;

        end if;
    end process;

end architecture rtl;