//=====================================================================
//vJTAG_interface
//UB. DSSD
//Grup:		Jefferson
//			Alvaro
//			Arnau		
//====================================================================

//====================================================================
//MODUL amb les senyals que utilitzarem
//===================================================================
module vJTAG_interface (
	 
		tck, 		
		tdi, 		
		tdo,
		ir_in,		
		v_sdr,
		v_cdr, 		
		v_udr,		
		aclr,
		rst_fifo,
		push_fifo,
		pop_fifo,
		full_fifo,
		empty_fifo,		
		Data_in,
		Data_out
);

//====================================================================
//DEFINICIO DE LES SENYALS
//====================================================================
//---------SENYALS DE CONTROL--------------------
input 		tck; 			//tck: Senyal de clock del vjtag_interface
input		tdi;			//tdi: Senyal de dades d'entrada 1 Bit
input [2:0]		ir_in;			//ir_in: Senyal d'instruccions, en aquest cas 1Bit
input		v_sdr; 			//v_sdr: Senyal que ens indica el Shift-DR
input		v_cdr;			//v_cdr: Senyal que ens indica el Capture-DR
input		v_udr;			//v_udr: virtual_state_udr (Update DR). En indica quan hem acabat de carregar la nova dada
input		aclr;			//aclr: reset del modul del vjtag_interface	
output reg 	tdo;			//tdo: Senyal de dades de sortida 1 Bit
//---------SENYALS FIFO--------------------------
output reg rst_fifo;		//rst_fifo: Per resetejar la fifo
output reg push_fifo;		//push_fifo: Quan volguem escriure push_fifo=1
output reg pop_fifo;		//pop_fifo: Quan volguem llegir pop_fifo=1
input full_fifo;			//full_fifo: Si full_fifo=1 no podem escriure
input empty_fifo;			//empty_fifo:Si empty_fifo=1 no podem llegir	
//------BUS DE DADES----------------------------
input 		[7:0] Data_in;	//Bus amb les dades que rep el vjtag_interface
output reg 	[7:0] Data_out;	//Bus amb les dades que envia el vjtag_interface

//=====================================================================
//DEFINICIONS I REGISTRES
//====================================================================

`define	WRITE		3'b001		//Funcio de escriure
`define READ		3'b000		//Funcio de llegir
`define	STATUS		3'b010		//Funcio de llegir els estats

reg [7:0]	DR1; 					//Registre on carregar les dades en Shift-DR
reg cdr_delayed;					//Capture Data Register delayed by half a clock cycle
reg sdr_delayed;					//Shift Data Register delayed by half a clock cycle
reg PUSH;							//Registres de control de PUSH i POP
/*De moment no el necessitem*/reg POP;									//??ESTIC DUPLICANT ELS REGISTRES ??

//=====================================================================
//CODI
//=====================================================================


//----------Carrega del valors de CDR i SDR----------------------------
always @(negedge tck)
begin
	//  Delay the CDR signal by one half clock cycle 
	cdr_delayed = v_cdr;
	sdr_delayed = v_sdr;
end

//---------------Control del reset i de les instruccions---------------
always @ (posedge tck or posedge aclr)
begin
	if (aclr)
		begin		
			DR1 <= 8'b0000000;
			//
			PUSH <=1'b0;
			POP  <=1'b0;
			//			
			rst_fifo	<= 1'b1;	//Amb el reset del vjtag_interface fem també el rst de la FIFO	
		end
	else		
		begin
			rst_fifo <= 1'b0;
			//
			PUSH <= 1'b0;
			POP  <= 1'b0;
			//

			case(ir_in)
			  
				`WRITE:					//Instruccio WRITE => ir_in =1. En aquest estat POP sempre sera 0
					begin
						if (!full_fifo)		//La FIFO no esta plena i encara podem esciure-hi dades
							begin
								PUSH <=1'b1;			//Si la fifo no esta plena i volem escriure PUSH=1.	
								if(sdr_delayed)			//El control de full_fifo el fem a v_udr
									begin				
										DR1 <= {tdi, DR1[7:1]}; 	//Desplacem una posició cap a la dreta els valors de DR1, eliminant
																	//el bit menys significatiu, i col·locant tdi en el bit més significatiu.
									end
								else					//Si no escrivim en la fifo fem el control del senyals push i enable
									begin

										bypass();
									end
							end
						else	//La FIFO esta plena
							bypass();	
					end
				`READ:					//Instruccio READ => ir_in=0. En aquest estat PUSH sempre és 0
					begin
						if(!empty_fifo)				//Podem llegir, hi han dades a la FIFO
							begin
								if(cdr_delayed)				//Utilitzem l'estat Capture-DR per carregar el valor a llegir
									begin					
										DR1 <= Data_in;			// Escribim el valor de Data_in
									end
								else
									if(sdr_delayed)			//Si ens trobem en l'estat Shift-DR podem passar les dades a tdo
										begin
											DR1 <= {tdi,DR1[7:1]};	//--!!--utilitzem la senyal tdi per buidar el registre 
																	//i a la vegada mantenir la comunicacio
										end
									else
									begin
										bypass();
									end
							end
						else							//La FIFO esta buida i no podem llegir
							begin
								bypass();
							end
					end
				
				`STATUS:				// Process status request (only  4 bits are required to be shifted)
					begin
						if( cdr_delayed )
							DR1 = {4'b0000, pop_fifo, push_fifo, empty_fifo, full_fifo};
						else 
						if( sdr_delayed )	
							DR1 = {tdi,DR1[7:1]};
					end
				default:
					begin
						bypass();
					end
			endcase				
		end
end

//-------Maintain the TDO Continuity-----------------------------------
always @ (*)
begin
	//if (ir_in==0 && !pop_fifo)//EDIT-12	//Si ir_in = 0 (mode LECTURA) i POP = 1 llegim i empty_fifo =0
	if (ir_in==0 || ir_in==2)
		begin
			//pop_fifo <= POP;
			tdo <= DR1[0];		
		end
	else
		begin
			tdo <= tdo;								//Si tenim seleccionat la instruccio d'escriure,
														//li passem 'uns' a tdo per mantenir la comunicacio
		end
end

//-----Capture-DR-------------------  La intenció d'aquest codi es enviar la senyal de pop un cicle abans de caputrar la dada.
always @(v_cdr)
begin
	if(ir_in==0)
		if(!empty_fifo)
			pop_fifo <= 1'b1;		//Enviem el senyal de llegir només si ir_in = 0 (lectura) i la fifo no esta buida
		else
			pop_fifo <= 1'b0;
	else
		pop_fifo <= 1'b0;
end

//-----Update-DR-----------------------		//Utilitzem aquest estat per assegurar-nos que tenim carregada la dada a escriure en DR1, i per tant,
											//ja la podem passar a Data_out
//--AQUEST ESTAT L'UTILITZEM PER ESCRIURE--											
always @(v_udr)
begin
	//if(!full_fifo)
	if(ir_in==1)
		begin
			if(!full_fifo)
				begin
				Data_out <= DR1;				//Passem la dada a escriure
				push_fifo <= PUSH;
				end
			else
				begin
				push_fifo <= PUSH;
				bypass();				//!!!VIGILAR AMB AQUESTA LINIA----
				end
		end
	else 							//BYPASS i control de PUSH
		begin
			bypass();
			push_fifo <= PUSH;

		end
end

task bypass;			//Executarem la tasca "bypass" quan per algun motiu no poguem executar la instruccio prevista
						//L'objectiu es deixar per defecte tots els valors i que no canvii res del sistema
						//Per exemple executarem la tasca "bypass" quan volguem escriure per fifo_full =1.
	begin
		DR1 	<= DR1;
		Data_out <= Data_out;
	
	end
endtask
/*
task PUSH_POP;			//Aquesta tasca ens escriu en els registres PUSH i POP.
	input i_PUSH, i_POP;
	begin
		//push_fifo <=i_PUSH;
		pop_fifo <= i_POP;
		PUSH 	<= i_PUSH;
		//POP 	<= i_POP;
	end
endtask
*/

endmodule

