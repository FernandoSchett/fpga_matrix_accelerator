library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity matrix_mult_4x4_top is
    generic (
        DATA_WIDTH : integer := 16;
        ACC_WIDTH  : integer := 32
    );
    port (
        clk   : in std_logic;
        rst   : in std_logic;

        wr_en      : in std_logic;
        matrix_sel : in std_logic; -- '0' = A, '1' = B
        wr_addr    : in unsigned(3 downto 0); -- 0..15
        data_in    : in signed(DATA_WIDTH-1 downto 0);

        start : in std_logic;
        busy  : out std_logic;
        done  : out std_logic;

        result_sel : in unsigned(3 downto 0); -- 0..15
        data_out   : out signed(ACC_WIDTH-1 downto 0)
    );
end entity matrix_mult_4x4_top;

architecture rtl of matrix_mult_4x4_top is

    subtype data_t is signed(DATA_WIDTH-1 downto 0);
    subtype acc_t  is signed(ACC_WIDTH-1 downto 0);

    type matrix_data_t is array (0 to 15) of data_t;
    type matrix_acc_t  is array (0 to 15) of acc_t;

    type state_t is (
        IDLE,
        CLEAR_C,
        START_CORE,
        WAIT_CORE,
        WRITE_BLOCK,
        DONE_STATE
    );

    signal state : state_t := IDLE;

    signal a_reg : matrix_data_t := (others => (others => '0'));
    signal b_reg : matrix_data_t := (others => (others => '0'));
    signal c_reg : matrix_acc_t  := (others => (others => '0'));

    signal block_row : integer range 0 to 1 := 0;
    signal block_col : integer range 0 to 1 := 0;
    signal block_k   : integer range 0 to 1 := 0;

    signal core_start : std_logic := '0';
    signal core_done  : std_logic;

    signal core_a00 : data_t := (others => '0');
    signal core_a01 : data_t := (others => '0');
    signal core_a10 : data_t := (others => '0');
    signal core_a11 : data_t := (others => '0');

    signal core_b00 : data_t := (others => '0');
    signal core_b01 : data_t := (others => '0');
    signal core_b10 : data_t := (others => '0');
    signal core_b11 : data_t := (others => '0');

    signal core_c00_in : acc_t := (others => '0');
    signal core_c01_in : acc_t := (others => '0');
    signal core_c10_in : acc_t := (others => '0');
    signal core_c11_in : acc_t := (others => '0');

    signal core_c00_out : acc_t;
    signal core_c01_out : acc_t;
    signal core_c10_out : acc_t;
    signal core_c11_out : acc_t;

    signal busy_reg : std_logic := '0';
    signal done_reg : std_logic := '0';

begin

    busy <= busy_reg;
    done <= done_reg;

    data_out <= c_reg(to_integer(result_sel));

    --------------------------------------------------------------------
    -- Seleção do bloco A(block_row, block_k)
    --------------------------------------------------------------------

    core_a00 <= a_reg((block_row * 2 + 0) * 4 + (block_k * 2 + 0));
    core_a01 <= a_reg((block_row * 2 + 0) * 4 + (block_k * 2 + 1));
    core_a10 <= a_reg((block_row * 2 + 1) * 4 + (block_k * 2 + 0));
    core_a11 <= a_reg((block_row * 2 + 1) * 4 + (block_k * 2 + 1));

    --------------------------------------------------------------------
    -- Seleção do bloco B(block_k, block_col)
    --------------------------------------------------------------------

    core_b00 <= b_reg((block_k * 2 + 0) * 4 + (block_col * 2 + 0));
    core_b01 <= b_reg((block_k * 2 + 0) * 4 + (block_col * 2 + 1));
    core_b10 <= b_reg((block_k * 2 + 1) * 4 + (block_col * 2 + 0));
    core_b11 <= b_reg((block_k * 2 + 1) * 4 + (block_col * 2 + 1));

    --------------------------------------------------------------------
    -- Seleção do bloco C(block_row, block_col)
    --------------------------------------------------------------------

    core_c00_in <= c_reg((block_row * 2 + 0) * 4 + (block_col * 2 + 0));
    core_c01_in <= c_reg((block_row * 2 + 0) * 4 + (block_col * 2 + 1));
    core_c10_in <= c_reg((block_row * 2 + 1) * 4 + (block_col * 2 + 0));
    core_c11_in <= c_reg((block_row * 2 + 1) * 4 + (block_col * 2 + 1));

    --------------------------------------------------------------------
    -- Core 2x2 reutilizado como tile engine
    --------------------------------------------------------------------

    u_core : entity work.matrix_mult_core
        generic map (
            DATA_WIDTH => DATA_WIDTH,
            ACC_WIDTH  => ACC_WIDTH
        )
        port map (
            clk   => clk,
            rst   => rst,
            start => core_start,
            done  => core_done,

            a00 => core_a00,
            a01 => core_a01,
            a10 => core_a10,
            a11 => core_a11,

            b00 => core_b00,
            b01 => core_b01,
            b10 => core_b10,
            b11 => core_b11,

            c00_in => core_c00_in,
            c01_in => core_c01_in,
            c10_in => core_c10_in,
            c11_in => core_c11_in,

            c00 => core_c00_out,
            c01 => core_c01_out,
            c10 => core_c10_out,
            c11 => core_c11_out
        );

    --------------------------------------------------------------------
    -- Controle principal
    --------------------------------------------------------------------

    process(clk, rst)
    begin
        if rst = '1' then
            state      <= IDLE;
            a_reg      <= (others => (others => '0'));
            b_reg      <= (others => (others => '0'));
            c_reg      <= (others => (others => '0'));
            block_row  <= 0;
            block_col  <= 0;
            block_k    <= 0;
            core_start <= '0';
            busy_reg   <= '0';
            done_reg   <= '0';

        elsif rising_edge(clk) then

            core_start <= '0';

            case state is

                when IDLE =>
                    busy_reg <= '0';
                    done_reg <= '0';

                    if wr_en = '1' then
                        if matrix_sel = '0' then
                            a_reg(to_integer(wr_addr)) <= data_in;
                        else
                            b_reg(to_integer(wr_addr)) <= data_in;
                        end if;
                    end if;

                    if start = '1' then
                        c_reg     <= (others => (others => '0'));
                        block_row <= 0;
                        block_col <= 0;
                        block_k   <= 0;
                        busy_reg  <= '1';
                        state     <= CLEAR_C;
                    end if;

                when CLEAR_C =>
                    busy_reg <= '1';
                    done_reg <= '0';
                    state    <= START_CORE;

                when START_CORE =>
                    busy_reg   <= '1';
                    done_reg   <= '0';
                    core_start <= '1';
                    state      <= WAIT_CORE;

                when WAIT_CORE =>
                    busy_reg <= '1';
                    done_reg <= '0';

                    if core_done = '1' then
                        state <= WRITE_BLOCK;
                    end if;

                when WRITE_BLOCK =>
                    c_reg((block_row * 2 + 0) * 4 + (block_col * 2 + 0)) <= core_c00_out;
                    c_reg((block_row * 2 + 0) * 4 + (block_col * 2 + 1)) <= core_c01_out;
                    c_reg((block_row * 2 + 1) * 4 + (block_col * 2 + 0)) <= core_c10_out;
                    c_reg((block_row * 2 + 1) * 4 + (block_col * 2 + 1)) <= core_c11_out;

                    if block_k = 0 then
                        block_k <= 1;
                        state   <= START_CORE;
                    else
                        block_k <= 0;

                        if block_col = 0 then
                            block_col <= 1;
                            state     <= START_CORE;
                        else
                            block_col <= 0;

                            if block_row = 0 then
                                block_row <= 1;
                                state     <= START_CORE;
                            else
                                state <= DONE_STATE;
                            end if;
                        end if;
                    end if;

                when DONE_STATE =>
                    busy_reg <= '0';
                    done_reg <= '1';

                    if start = '0' then
                        state <= IDLE;
                    end if;

            end case;

        end if;
    end process;

end architecture rtl;