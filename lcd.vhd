library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;



entity lcd is
    Port (
       --- inclusao para kb_code
       ps2d, ps2c: in  std_logic;
       --- 
       LCD_DB: out std_logic_vector(7 downto 0);		
       --DB( 7 through 0)
       RS:out std_logic;                --WE
       RW:out std_logic;                --ADR(0)
       CLK:in std_logic;                --GCLK2
       --ADR1:out std_logic;            --ADR(1)
       --ADR2:out std_logic;            --ADR(2)
       --CS:out std_logic;              --CSC
       OE:out std_logic;                --OE
       KBE:out std_logic;               -- kb_buf_empty
       LEDS: out std_logic_vector(7 downto 0); -- key_code para os LEDs
       rst:in std_logic		);		--BTN
       --rdone: out std_logic);     --WriteDone output to work with DI05 test
end lcd;

architecture Behavioral of lcd is
			    
------------------------------------------------------------------
--  Component Declarations
------------------------------------------------------------------

----INCLUSAO DA FUNCAO KB_CODE PARA LER O TECLADO
component kb_code is
   generic(W_SIZE: integer:=2);  -- 2^W_SIZE words in FIFO
   port (
      clk, reset: in  std_logic;
      ps2d, ps2c: in  std_logic;
      rd_key_code: in std_logic;
      key_code: out std_logic_vector(7 downto 0);
      kb_buf_empty: out std_logic
   );
end component kb_code;

----INCLUSAO DA FUNCAO KEY_2_ASCII PARA CONVERTER AS TECLAS PARA O CODIGO ASCII
component key2ascii is
   port (
      key_code: in std_logic_vector(7 downto 0);
      ascii_code: out std_logic_vector(7 downto 0)
   );
end component key2ascii;

------------------------------------------------------------------
--  Local Type Declarations
-----------------------------------------------------------------
--  Symbolic names for all possible states of the state machines.

	--LCD control state machine
	type mstate is (					  
		stFunctionSet,		 	--Initialization states
		stDisplayCtrlSet,
		stDisplayClear,
		stPowerOn_Delay,  		--Delay states
		stFunctionSet_Delay,
		stDisplayCtrlSet_Delay, 	
		stDisplayClear_Delay,
		stInitDne,			--Display charachters and perform standard operations
		stActWr,
		stCharDelay		--Write delay for operations
		--stWait			--Idle state
	);

	--Write control state machine
	type wstate is (
		stRW,			--set up RS and RW
		stEnable,		--set up E
		stIdle			--Write data on DB(0)-DB(7)
	);

------------------------------------------------------------------
--  Signal Declarations and Constants

    signal clkCount:std_logic_vector(5 downto 0);
    signal activateW:std_logic:= '0';		    			--Activate Write sequence
    signal count:std_logic_vector (16 downto 0):= "00000000000000000";	--15 bit count variable for timing delays
    signal delayOK:std_logic:= '0';						--High when count has reached the right delay time
    signal OneUSClk:std_logic;						--Signal is treated as a 1 MHz clock	
    signal stCur:mstate:= stPowerOn_Delay;					--LCD control state machine
    signal stNext:mstate;			  	
    signal stCurW:wstate:= stIdle; 						--Write control state machine
    signal stNextW:wstate;
    signal writeDone:std_logic;					--Command set finish
    ------- signals para kb_code
    signal rd_key_code: std_logic:= '0';
    signal key_code: std_logic_vector(7 downto 0);
    signal kb_buf_empty: std_logic;
	------- signals para key2ascii
    signal tecla : std_logic_vector(7 downto 0); --ascii_code
	
	-------- signals para logica do jogo
    signal start: std_logic;
    signal palavra_certa : std_logic_vector (3 downto 0) := "0000";
	-- bit 3 - indica se a palavra inteira está certa
	-- bit 2 - indica se a letra D foi encontrada
	-- bit 1 - indica se a letra I foi encontrada
	-- bit 0 - indica se a letra O doi encontrada
	--- >>> Palavra escolhida : DIODO
	
						 
    type LCD_CMDS_T is array(integer range 0 to 30) of std_logic_vector(9 downto 0);
    signal LCD_CMDS : LCD_CMDS_T := ( 
                        0 => "00"&X"3C",            --Function Set
                        1 => "00"&X"0C",			--Display ON, Cursor OFF, Blink OFF
                        2 => "00"&X"01",			--Clear Display
                        3 => "00"&X"02", 		--return home
                        4 => "10"&X"4A", 		-- J
                        5 => "10"&X"6F",  		-- o
                        6 => "10"&X"67",  		-- g
                        7 => "10"&X"6f", 		-- o
                        8 => "10"&X"20", 		-- 
                        9 => "10"&X"64",  		-- d
                        10 => "10"&X"61", 		-- a
                        11 => "10"&X"20", 		--
                        12 => "10"&X"46", 		-- F
                        13 => "10"&X"6f", 		-- o		
                        14 => "10"&X"72",		-- r
                        15 => "10"&X"63", 		-- c
                        16 => "10"&X"61", 		-- a
                        17 => "10"&X"20",		-- 
                        18 => "00"&X"C0",		-- 
                        19 => "10"&X"74",		-- t 
                        20 => "10"&X"65",		-- e
                        21 => "10"&X"63",		-- c
                        22 => "10"&X"6c",		-- l
                        23 => "10"&X"65",		-- e
                        24 => "10"&X"20",		-- 
                        25 => "10"&X"61",		-- a
                        26 => "10"&X"6c",		-- l
                        27 => "10"&X"67",		-- g
                        28 => "10"&X"6f",		-- o
                        29 => "10"&X"20",		-- 
                        30 => "00"&X"02");		-- return home

													
    signal lcd_cmd_ptr : integer range 0 to LCD_CMDS'HIGH + 1 := 0;
begin
	
	--- LEITURA DO TECLADO
    label0 : kb_code port map(CLK,rst,ps2d,ps2c,rd_key_code,key_code,kb_buf_empty);
	--label0 : kb_code port map(CLK,rst,ps2d,ps2c,rd_key_code,key_code,kb_buf_empty);
    KBE <= kb_buf_empty;
    LEDS <= key_code;
	
	--- CONVERSAO PARA ASCII
    label1 : key2ascii port map (key_code , tecla);
	
	

	--  This process counts to 50, and then resets.  It is used to divide the clock signal time.
    process (CLK, oneUSClk)
        begin
            if (CLK = '1' and CLK'event) then
				clkCount <= clkCount + 1;
            end if;
        end process;
	--  This makes oneUSClock peak once every 1 microsecond

    oneUSClk <= clkCount(5);
	--  This process incriments the count variable unless delayOK = 1.
    process (oneUSClk, delayOK)
        begin
            if (oneUSClk = '1' and oneUSClk'event) then
                if delayOK = '1' then
                    count <= "00000000000000000";
                else
                    count <= count + 1;
                end if;
            end if;
    end process;

    --This goes high when all commands have been run
    writeDone <= '1' when (lcd_cmd_ptr = LCD_CMDS'HIGH) 
        else '0';
	--rdone <= '1' when stCur = stWait else '0';
	--Increments the pointer so the statemachine goes through the commands
    process (lcd_cmd_ptr, oneUSClk)
    begin
	
        if (oneUSClk = '1' and oneUSClk'event) then
            if ((stNext = stInitDne or stNext = stDisplayCtrlSet or stNext = stDisplayClear) and writeDone = '0') then 
                lcd_cmd_ptr <= lcd_cmd_ptr + 1;
            elsif stCur = stPowerOn_Delay or stNext = stPowerOn_Delay then
                lcd_cmd_ptr <= 0;
                ------------------------------------------	
            elsif lcd_cmd_ptr = 30 then
                lcd_cmd_ptr <= 3;
                ------------------------------------------
            else
                lcd_cmd_ptr <= lcd_cmd_ptr;
            end if;
        end if;
    end process;
	
	--  Determines when count has gotten to the right number, depending on the state.

    delayOK <= '1' when ((stCur = stPowerOn_Delay and count = "00100111001010010") or 			--20050  
                    (stCur = stFunctionSet_Delay and count = "00000000000110010") or	--50
                    (stCur = stDisplayCtrlSet_Delay and count = "00000000000000010") or	--50
                    --(stCur = stDisplayCtrlSet_Delay and count = "00000000000110010") or	--50
                    (stCur = stDisplayClear_Delay and count = "00000011001000000") or	--1600
                    (stCur = stCharDelay and count = "11111111111111111"))			--Max Delay for character writes and shifts
                    --(stCur = stCharDelay and count = "00000000000100101"))		--37  This is proper delay between writes to ram.
		else	'0';
  	
	-- This process runs the LCD status state machine
	process (oneUSClk, rst)
		begin
			if oneUSClk = '1' and oneUSClk'Event then
				if rst = '1' then
					stCur <= stPowerOn_Delay;
				else
					stCur <= stNext;
				end if;
			end if;
		end process;

	
	--  This process generates the sequence of outputs needed to initialize and write to the LCD screen
    process (stCur, delayOK, writeDone, lcd_cmd_ptr)
        begin   
		
            case stCur is
			
                --  Delays the state machine for 20ms which is needed for proper startup.
				when stPowerOn_Delay =>
                    if delayOK = '1' then
                        stNext <= stFunctionSet;
                    else
                        stNext <= stPowerOn_Delay;
                    end if;
                    RS <= LCD_CMDS(lcd_cmd_ptr)(9);
                    RW <= LCD_CMDS(lcd_cmd_ptr)(8);
                    LCD_DB <= LCD_CMDS(lcd_cmd_ptr)(7 downto 0);
                    activateW <= '0';

                -- This issuse the function set to the LCD as follows 
                -- 8 bit data length, 2 lines, font is 5x8.
                when stFunctionSet =>
                    RS <= LCD_CMDS(lcd_cmd_ptr)(9);
                    RW <= LCD_CMDS(lcd_cmd_ptr)(8);
                    LCD_DB <= LCD_CMDS(lcd_cmd_ptr)(7 downto 0);
                    activateW <= '1';	
                    stNext <= stFunctionSet_Delay;
				
                --Gives the proper delay of 37us between the function set and
                --the display control set.
                when stFunctionSet_Delay =>
                    RS <= LCD_CMDS(lcd_cmd_ptr)(9);
                    RW <= LCD_CMDS(lcd_cmd_ptr)(8);
                    LCD_DB <= LCD_CMDS(lcd_cmd_ptr)(7 downto 0);
                    activateW <= '0';
                    if delayOK = '1' then
                        stNext <= stDisplayCtrlSet;
                    else
                        stNext <= stFunctionSet_Delay;
                    end if;
				
                --Issuse the display control set as follows
                --Display ON,  Cursor OFF, Blinking Cursor OFF.
                when stDisplayCtrlSet =>
                    RS <= LCD_CMDS(lcd_cmd_ptr)(9);
                    RW <= LCD_CMDS(lcd_cmd_ptr)(8);
                    LCD_DB <= LCD_CMDS(lcd_cmd_ptr)(7 downto 0);
                    activateW <= '1';
                    stNext <= stDisplayCtrlSet_Delay;

                --Gives the proper delay of 37us between the display control set
                --and the Display Clear command. 
                when stDisplayCtrlSet_Delay =>
                    RS <= LCD_CMDS(lcd_cmd_ptr)(9);
                    RW <= LCD_CMDS(lcd_cmd_ptr)(8);
                    LCD_DB <= LCD_CMDS(lcd_cmd_ptr)(7 downto 0);
                    activateW <= '0';
                    if delayOK = '1' then
                        stNext <= stDisplayClear;
                    else
                        stNext <= stDisplayCtrlSet_Delay;
                    end if;
				
                --Issues the display clear command.
                when stDisplayClear	=>
                    RS <= LCD_CMDS(lcd_cmd_ptr)(9);
                    RW <= LCD_CMDS(lcd_cmd_ptr)(8);
                    LCD_DB <= LCD_CMDS(lcd_cmd_ptr)(7 downto 0);
                    activateW <= '1';
                    stNext <= stDisplayClear_Delay;

                --Gives the proper delay of 1.52ms between the clear command
                --and the state where you are clear to do normal operations.
                when stDisplayClear_Delay =>
                    RS <= LCD_CMDS(lcd_cmd_ptr)(9);
                    RW <= LCD_CMDS(lcd_cmd_ptr)(8);
                    LCD_DB <= LCD_CMDS(lcd_cmd_ptr)(7 downto 0);
                    activateW <= '0';
                    if delayOK = '1' then
                        stNext <= stInitDne;
                    else
                        stNext <= stDisplayClear_Delay;
                    end if;
				
                --State for normal operations for displaying characters, changing the
                --Cursor position etc.
                when stInitDne =>		
                    RS <= LCD_CMDS(lcd_cmd_ptr)(9);
                    RW <= LCD_CMDS(lcd_cmd_ptr)(8);
                    LCD_DB <= LCD_CMDS(lcd_cmd_ptr)(7 downto 0);
                    activateW <= '0';
                    stNext <= stActWr;

                when stActWr =>		
                    RS <= LCD_CMDS(lcd_cmd_ptr)(9);
                    RW <= LCD_CMDS(lcd_cmd_ptr)(8);
                    LCD_DB <= LCD_CMDS(lcd_cmd_ptr)(7 downto 0);
                    activateW <= '1';
                    stNext <= stCharDelay;
					
                --Provides a max delay between instructions.
                when stCharDelay =>
                    RS <= LCD_CMDS(lcd_cmd_ptr)(9);
                    RW <= LCD_CMDS(lcd_cmd_ptr)(8);
                    LCD_DB <= LCD_CMDS(lcd_cmd_ptr)(7 downto 0);
                    activateW <= '0';					
                    if delayOK = '1' then
                        stNext <= stInitDne;
                    else
                        stNext <= stCharDelay;
                    end if;
            end case;
		
        end process;					
								   
 	--This process runs the write state machine
	process (oneUSClk, rst)
		begin
			if oneUSClk = '1' and oneUSClk'Event then
				if rst = '1' then
					stCurW <= stIdle;
				else
					stCurW <= stNextW;
				end if;
			end if;
		end process;

	--This genearates the sequence of outputs needed to write to the LCD screen
    process (stCurW, activateW)
        begin   
		
            case stCurW is
                --This sends the address across the bus telling the DIO5 that we are
                --writing to the LCD, in this configuration the adr_lcd(2) controls the
                --enable pin on the LCD
                when stRw =>
                    OE <= '0';
                    --CS <= '0';
                    --ADR2 <= '1';
                    --ADR1 <= '0';
                    stNextW <= stEnable;
				
                --This adds another clock onto the wait to make sure data is stable on 
                --the bus before enable goes low.  The lcd has an active falling edge 
                --and will write on the fall of enable
                when stEnable => 
                    OE <= '0';
                    --CS <= '0';
                    --ADR2 <= '0';
                    --ADR1 <= '0';
                    stNextW <= stIdle;
				
                --Waiting for the write command from the instuction state machine
                when stIdle =>
                    --ADR2 <= '0';
                    --ADR1 <= '0';
                    --CS <= '1';
                    OE <= '1';
                    if activateW = '1' then
                        stNextW <= stRw;
                    else
                        stNextW <= stIdle;
                    end if;
                end case;
        end process;
		
	
------ estado para verificar se a letra pertence a palavra ------------------------	
    process(oneUSCLk)
        variable vidas:integer := 5;
    begin
        if (oneUSClk = '1' and oneUSClk'Event) then
			
            if rst = '1' then
                palavra_certa <= "0000";
                vidas := 5;
                start <= '0';
                LCD_CMDS (4) <= "10"&X"4A"; -- J
                LCD_CMDS (5) <= "10"&X"6F"; -- o
                LCD_CMDS (6) <= "10"&X"67"; -- g
                LCD_CMDS (7) <= "10"&X"6F"; -- o
                LCD_CMDS (8) <= "10"&X"20"; --
                LCD_CMDS (9) <= "10"&X"64"; -- d
                LCD_CMDS (10) <= "10"&X"61";-- a
                LCD_CMDS (11) <= "10"&X"20";--
                LCD_CMDS (12) <= "10"&X"46";-- F
                LCD_CMDS (13) <= "10"&X"6f";-- o
                LCD_CMDS (14) <= "10"&X"72";-- r
                LCD_CMDS (15) <= "10"&X"63";-- c
                LCD_CMDS (16) <= "10"&X"61";-- a
                LCD_CMDS (17) <= "10"&X"20";-- 
                LCD_CMDS (18) <= "00"&X"C0";-- 
                LCD_CMDS (19) <= "10"&X"74";-- t 
                LCD_CMDS (20) <= "10"&X"65";-- e
                LCD_CMDS (21) <= "10"&X"63";-- c
                LCD_CMDS (22) <= "10"&X"6c";-- l
                LCD_CMDS (23) <= "10"&X"65";-- e
                LCD_CMDS (24) <= "10"&X"20";-- 
                LCD_CMDS (25) <= "10"&X"61";-- a
                LCD_CMDS (26) <= "10"&X"6c";-- l
                LCD_CMDS (27) <= "10"&X"67";-- g
                LCD_CMDS (28) <= "10"&X"6f";-- o
                LCD_CMDS (29) <= "10"&X"20";-- 	
					
            end if;
			
            if (kb_buf_empty = '1') then
               rd_key_code <= '0';
            end if;
            
			--- mudanca no visor para o inicio do jogo 	
            if (kb_buf_empty = '0') and (start = '0') then
               start <= '1';
               LCD_CMDS (4)  <= "10"&X"5F"; -- _
               LCD_CMDS (5)  <= "10"&X"5F"; -- _
               LCD_CMDS (6)  <= "10"&X"5F"; -- _
               LCD_CMDS (7)  <= "10"&X"5F"; -- _
               LCD_CMDS (8)  <= "10"&X"5F"; -- _
               LCD_CMDS (9)  <= "10"&X"20"; --
               LCD_CMDS (10) <= "10"&X"20"; --
               LCD_CMDS (11) <= "10"&X"20"; --
               LCD_CMDS (12) <= "10"&X"20"; --
               LCD_CMDS (13) <= "10"&X"20"; --
               LCD_CMDS (14) <= "10"&X"20"; --
               LCD_CMDS (15) <= "10"&X"20"; --
               LCD_CMDS (16) <= "10"&X"20"; --
               LCD_CMDS (17) <= "10"&X"35"; -- 5
               LCD_CMDS (18) <= "00"&X"C0"; -- "pular linha" 
               LCD_CMDS (19) <= "10"&X"20"; --  
               LCD_CMDS (20) <= "10"&X"20"; -- 
               LCD_CMDS (21) <= "10"&X"20"; -- 
               LCD_CMDS (22) <= "10"&X"20"; -- 
               LCD_CMDS (23) <= "10"&X"20"; -- 
               LCD_CMDS (24) <= "10"&X"20"; -- 
               LCD_CMDS (25) <= "10"&X"20"; -- 
               LCD_CMDS (26) <= "10"&X"20"; -- 
               LCD_CMDS (27) <= "10"&X"20"; -- 
               LCD_CMDS (28) <= "10"&X"20"; -- 
               LCD_CMDS (29) <= "10"&X"20"; -- 	
               rd_key_code <= '1';
            end if;
			
            --- analise das teclas
            if ((start = '1') and (vidas > 0) and (kb_buf_empty = '0') and (palavra_certa /= "1111")) then 
               
               case tecla is
                   when X"44" => --- verifica se a letra salva foi D
                           if (palavra_certa(2) = '0') then -- D____
                               palavra_certa(2) <= '1';
						end if;
					
                   when X"49" => -- verifica se a letra salva foi I
                           if (palavra_certa(1) = '0') then -- _I___
                               palavra_certa(1) <= '1';
						end if;
					
                   when X"4F" => -- verifica se a letra salva foi O
                           if (palavra_certa(0) = '0') then -- __O__
                               palavra_certa(0) <= '1';
						end if;
                   when others =>
                           vidas := vidas - 1;
					
               end case;		
               rd_key_code <= '1'; 
            end if;
			
			--- palavra encontrada
            if (palavra_certa = "0111") then
               palavra_certa <= "1111";
            end if;
		
--------  trocar "_" pela letra certa (ou manter inalterado)
            if(start = '1') then
               if (palavra_certa(2) = '1') then
                   LCD_CMDS(4) <= "10"&X"44"; -- escreve D
                   LCD_CMDS(7) <= "10"&X"44";
               else 
                   LCD_CMDS(4) <= "10"&X"5F";	
                   LCD_CMDS(7) <= "10"&X"5F";
               end if;
        		
               if (palavra_certa(1) = '1') then
                   LCD_CMDS(5) <= "10"&X"49"; -- escreve I
               else 
                   LCD_CMDS(5) <= "10"&X"5F";
               end if;
        		
               if (palavra_certa(0) = '1') then
                   LCD_CMDS(6) <= "10"&X"4F"; -- escreve O
                   LCD_CMDS(8) <= "10"&X"4F";
               else 
                   LCD_CMDS(6) <= "10"&X"5F"; 
                   LCD_CMDS(8) <= "10"&X"5F";
               end if;
            end if;

		
------- analise das vidas 
            if (vidas /= 5) then
    			case vidas is
    			
                   when 4 => 
                           LCD_CMDS(17) <= "10"&X"34"; -- escreve 4
    	
                   when 3 =>
                           LCD_CMDS(17) <= "10"&X"33"; -- escreve 3
    		
                   when 2 =>
                           LCD_CMDS(17) <= "10"&X"32"; -- escreve 2	
    			
                   when 1 =>
                           LCD_CMDS(17) <= "10"&X"31"; -- escreve 1
    				
                   when others => ------- estado "perdeu"
                           LCD_CMDS(17) <= "10"&X"30"; -- escreve 0
                           LCD_CMDS(4) <= LCD_CMDS(4);  
                           LCD_CMDS(5) <= LCD_CMDS(5);  
                           LCD_CMDS(6) <= LCD_CMDS(6); 	
                           LCD_CMDS(7) <= LCD_CMDS(7);  
                           LCD_CMDS(8) <= LCD_CMDS(8);  
                           LCD_CMDS(9) <= LCD_CMDS(9);  
                           LCD_CMDS(10) <= LCD_CMDS(10);  
                           LCD_CMDS(11) <= LCD_CMDS(11); 
                           LCD_CMDS(12) <= LCD_CMDS(12); 
                           LCD_CMDS(13) <= LCD_CMDS(13); 
                           LCD_CMDS(14) <= LCD_CMDS(14); 
                           LCD_CMDS(15) <= LCD_CMDS(15); 
                           LCD_CMDS(16) <= LCD_CMDS(16); 
                           LCD_CMDS(18) <= "00"&X"C0";-- 
                           LCD_CMDS(19) <= "10"&X"56";-- V
                           LCD_CMDS(20) <= "10"&X"4F";-- O
                           LCD_CMDS(21) <= "10"&X"43";-- C
                           LCD_CMDS(22) <= "10"&X"45";-- E
                           LCD_CMDS(23) <= "10"&X"20";-- 
                           LCD_CMDS(24) <= "10"&X"50";-- P
                           LCD_CMDS(25) <= "10"&X"45";-- E 
                           LCD_CMDS(26) <= "10"&X"52";-- R
                           LCD_CMDS(27) <= "10"&X"44";-- D
                           LCD_CMDS(28) <= "10"&X"45";-- E
                           LCD_CMDS(29) <= "10"&X"55";-- U
    				
                   end case;
            end if;

------ estado "ganhou"  	
            case palavra_certa is
                   when "1111" =>
                           LCD_CMDS(4) <= LCD_CMDS(4);  
                           LCD_CMDS(5) <= LCD_CMDS(5);  
                           LCD_CMDS(6) <= LCD_CMDS(6); 	
                           LCD_CMDS(7) <= LCD_CMDS(7);  
                           LCD_CMDS(8) <= LCD_CMDS(8);  
                           LCD_CMDS(9) <= LCD_CMDS(9);  
                           LCD_CMDS(10) <= LCD_CMDS(10);  
                           LCD_CMDS(11) <= LCD_CMDS(11); 
                           LCD_CMDS(12) <= LCD_CMDS(12); 
                           LCD_CMDS(13) <= LCD_CMDS(13); 
                           LCD_CMDS(14) <= LCD_CMDS(14); 
                           LCD_CMDS(15) <= LCD_CMDS(15); 
                           LCD_CMDS(16) <= LCD_CMDS(16); 
                           LCD_CMDS(17) <= LCD_CMDS(17); 
                           LCD_CMDS(18) <= "00"&X"C0";-- 
                           LCD_CMDS(19) <= "10"&X"56";-- V
                           LCD_CMDS(20) <= "10"&X"4F";-- O
                           LCD_CMDS(21) <= "10"&X"43";-- C
                           LCD_CMDS(22) <= "10"&X"45";-- E
                           LCD_CMDS(23) <= "10"&X"20";-- 
                           LCD_CMDS(24) <= "10"&X"47";-- G
                           LCD_CMDS(25) <= "10"&X"41";-- A 
                           LCD_CMDS(26) <= "10"&X"4E";-- N
                           LCD_CMDS(27) <= "10"&X"48";-- H
                           LCD_CMDS(28) <= "10"&X"4F";-- O
                           LCD_CMDS(29) <= "10"&X"55";-- U
    
    
                   when others =>
            end case;

--------------------
		end if;
	end process;					
end Behavioral;

--------------------