`timescale 1ns/1ns
module eeprom_wr
(
	input	wire			RESET,		//复位信号
	input 	wire			CLK,		//时钟信号输入
	input 	wire			WR,			//写信号
	input	wire			RD,			//读信号
	input	wire	[2:0]	ADDR_DEV,	//地址线，器件
	input	wire	[15:0]	ADDR,		//要写数据的地址
	inout 	wire			SDA,		//串行数据线
	input	wire	[7:0] 	DATA,		//并行数据线
	output	wire	[7:0] 	DATA_out,
	output	reg				SCL,		//串行时钟线
	output	reg				ACK			//读写一个周期的应答信号
);

reg 		WF;
reg			RF;					//读写操作标志
reg 		FF; 				//标志寄存器
reg	[1:0] 	head_buf;			//启动信号寄存器
reg	[1:0] 	stop_buf;			//停止信号寄存器
reg	[7:0] 	sh8out_buf;			//EEPROM写寄存器
(*keep = "true"*)reg	[8:0] 	sh8out_state;		//EEPROM写状态寄存器
(*keep = "true"*)reg	[9:0] 	sh8in_state;		//EEPROM读状态寄存器
(*keep = "true"*)reg	[2:0] 	head_state;			//启动状态寄存器
(*keep = "true"*)reg	[2:0] 	stop_state;			//停止状态寄存器
(*keep = "true"*)reg	[10:0]	main_state;			//主状态寄存器
reg	[7:0] 	data_from_rm;		//EEPROM读寄存器
reg 		link_sda;			//SDA数据输入EEPROM开关
reg 		link_read;			//EEPROM读操作开关
reg 		link_head;			//启动信号开关
reg 		link_write;			//EEPROM写操作开关
reg 		link_stop;			//停止信号开关
wire sda1, sda2, sda3, sda4;	//串行数据在开关控制下有秩序的输出或输入
assign sda1 = (link_head) ? head_buf[1] : 1'b0;
assign sda2 = (link_write) ? sh8out_buf[7] : 1'b0;
assign sda3 = (link_stop) ? stop_buf[1] : 1'b0;
assign sda4 = (sda1|sda2|sda3);
assign SDA 	= (link_sda) ? sda4 : 1'bz;
assign DATA_out = (link_read) ? data_from_rm : 8'hzz;
//主状态机状态定义
parameter
Idle		= 11'b00000000001,
Ready		= 11'b00000000010,
Write_start	= 11'b00000000100,
Ctrl_write	= 11'b00000001000,
Addr_write	= 11'b00000010000,
Data_write	= 11'b00000100000,
Read_start	= 11'b00001000000,
Ctrl_read 	= 11'b00010000000,
Data_read 	= 11'b00100000000,
Stop      	= 11'b01000000000,
Ackn      	= 11'b10000000000,
Addr_write1	= 11'b11111111111,
//并行数据串行输出状态
sh8out_bit7	= 9'b000000001,
sh8out_bit6	= 9'b000000010,
sh8out_bit5	= 9'b000000100,
sh8out_bit4	= 9'b000001000,
sh8out_bit3	= 9'b000010000,
sh8out_bit2	= 9'b000100000,
sh8out_bit1	= 9'b001000000,
sh8out_bit0	= 9'b010000000,
sh8out_end 	= 9'b100000000;
//串行数据并行输出状态
parameter
sh8in_begin	= 10'b0000000001,
sh8in_bit7 	= 10'b0000000010,
sh8in_bit6 	= 10'b0000000100,
sh8in_bit5 	= 10'b0000001000,
sh8in_bit4 	= 10'b0000010000,
sh8in_bit3 	= 10'b0000100000,
sh8in_bit2 	= 10'b0001000000,
sh8in_bit1 	= 10'b0010000000,
sh8in_bit0 	= 10'b0100000000,
sh8in_end  	= 10'b1000000000,
//启动状态
head_begin	= 3'b001,
head_bit  	= 3'b010,
head_end  	= 3'b100,
//停止状态
stop_begin	= 3'b001,
stop_bit  	= 3'b010,
stop_end  	= 3'b100;
parameter
YES	= 1,
NO	= 0;
//产生串行时钟SCL，为输入时钟的2分频
always @(negedge CLK)
if(RESET)
	SCL <= 0;
else
	SCL <= ~SCL;
//主状态机程序
always @(posedge CLK)
if(RESET)
	begin
		link_read<=NO;
		link_write<=NO;
		link_head<=NO;
		link_stop<=NO;
		link_sda<=NO;
		ACK<=0;
		FF<=0;
		RF<=0;
		WF<=0;

		main_state<=Idle;
	end
else
	begin
	casex(main_state)
	Idle:
		begin
		link_read<=NO;
		link_write<=NO;
		link_head<=NO;
		link_stop<=NO;
		link_sda<=NO;
		if(WR)
			begin
			WF<=1;
			main_state<=Ready;
			end
		else if(RD)
			begin
			RF<=1;
			main_state<=Ready;
			end
		else
			begin
			WF<=0;
			RF<=0;
			main_state<=Idle;
			end
		end
	Ready:
		begin
		link_read<=NO;
		link_write<=NO;
		link_stop<=NO;
		link_head<=YES;
		link_sda<=YES;
		head_buf[1:0]<=2'b10;
		stop_buf[1:0]<=2'b01;
		head_state<=head_begin;
		FF<=0;
		ACK<=0;
		main_state<=Write_start;
		end
Write_start:
	if(FF==0)
		shift_head;
	else
		begin
		sh8out_buf[7:0]<={1'b1,1'b0,1'b1,1'b0,ADDR_DEV,1'b0};
		link_head<=NO;
		link_write<=YES;
		FF<=0;
		sh8out_state<=sh8out_bit6;
		main_state<=Ctrl_write;
		end
Ctrl_write:
        if(FF==0)
        	shift8_out;
        else
		begin
			sh8out_state	<= sh8out_bit7;
			sh8out_buf[7:0]	<= ADDR[15:8];
			FF				<= 0;
			main_state		<= Addr_write;
		end
Addr_write:
        if(FF==0)
			shift8_out;
        else
		begin
			FF<=0;
			sh8out_state<=sh8out_bit7;
			sh8out_buf[7:0]<=ADDR[7:0];
			main_state<=Addr_write1;
		end
Addr_write1:
	begin
        if(FF==0)
                shift8_out;
		else
			begin
				FF<=0;
				if(WF)
				begin
					sh8out_state<=sh8out_bit7;
					sh8out_buf[7:0]<=DATA;
					main_state<=Data_write;
				end
				if(RF)
				begin
					head_buf<=2'b10;
					head_state<=head_begin;
					// main_state<=Read_start;
					main_state<=Ctrl_read;
				end
			end			
	end			  
Data_write:
          if(FF==0)
                  shift8_out;
          else
                  begin
                  stop_state<=stop_begin;
                  main_state<=Stop;
                  link_write<=NO;
		            FF<=0;
                  end
// Read_start:
          // if(FF==0)
                  // shift_head;
          // else
                  // begin
                  // sh8out_buf<={4'b1010,ADDR[10:8],1'b1};
                  // link_head<=NO;
                  // link_sda<=YES;
                  // link_write<=YES;
		            // FF<=0;
		            // sh8out_state<=sh8out_bit6;
                  // main_state<=Ctrl_read;
                  // end
Ctrl_read:
           if(FF==0)
                   shift8_out;
           else
                   begin
                   link_sda<=NO;
 		             link_write<=NO;
		             FF<=0;
                   sh8in_state<=sh8in_begin;
                   main_state<=Data_read;
                   end
Data_read:
          if(FF==0)
                  shift8in;
          else
                  begin
                  link_stop<=YES;
		            link_sda<=YES;
		            stop_state<=stop_bit;
                  FF<=0;
		            main_state<=Stop;
                  end
Stop:
	     if(FF==0)
                shift_stop;
        else
                begin
                ACK<=1;
		          FF<=0;
		          main_state<=Ackn;
                end
Ackn:
	     begin
        ACK<=0;
	     WF<=0;
	     RF<=0;
	     main_state<=Idle;
        end
default:
	main_state<=Idle;
endcase
end
//串行数据转换为并行数据任务
task shift8in;
begin
casex(sh8in_state)
    sh8in_begin:
        sh8in_state<=sh8in_bit7;
    sh8in_bit7:
       if(SCL)
         begin
         data_from_rm[7]<=SDA;
         sh8in_state<=sh8in_bit6;
         end
         else
         sh8in_state<=sh8in_bit7;
    sh8in_bit6:
       if(SCL)
         begin
         data_from_rm[6]<=SDA;
         sh8in_state<=sh8in_bit5;
         end
       else
         sh8in_state<=sh8in_bit6;
    sh8in_bit5:
       if(SCL)
         begin
         data_from_rm[5]<=SDA;
         sh8in_state<=sh8in_bit4;
         end
       else
         sh8in_state<=sh8in_bit5;
    sh8in_bit4:
       if(SCL)
         begin
         data_from_rm[4]<=SDA;
         sh8in_state<=sh8in_bit3;
         end
       else
         sh8in_state<=sh8in_bit4;
    sh8in_bit3:
      if(SCL)
         begin
         data_from_rm[3]<=SDA;
         sh8in_state<=sh8in_bit2;
         end
       else
         sh8in_state<=sh8in_bit3;
    sh8in_bit2:
       if(SCL)
         begin data_from_rm[2]<=SDA;
         sh8in_state<=sh8in_bit1;
         end
       else
         sh8in_state<=sh8in_bit2;
    sh8in_bit1:
       if(SCL)
         begin
         data_from_rm[1]<=SDA;
         sh8in_state<=sh8in_bit0;
         end
       else
         sh8in_state<=sh8in_bit1;
    sh8in_bit0:

       if(SCL)
         begin
         data_from_rm[0]<=SDA;
         sh8in_state<=sh8in_end;
         end
       else
         sh8in_state<=sh8in_bit0;
    sh8in_end:
       if(SCL)
         begin
         link_read<=YES;
         FF<=1;
         sh8in_state<=sh8in_bit7;
         end
       else
         sh8in_state<=sh8in_end;
   default:
	       begin
          link_read<=NO;
          sh8in_state<=sh8in_bit7;
          end
endcase
end
endtask
//并行数据转换为串行数据任务
task shift8_out;
begin
casex(sh8out_state)
sh8out_bit7:
   if(!SCL)
       begin
       link_sda<=YES;
       link_write<=YES;

       sh8out_state<=sh8out_bit6;
       end
    else
       sh8out_state<=sh8out_bit7;
sh8out_bit6:
   if(!SCL)
       begin
       link_sda<=YES;link_write<=YES;
       sh8out_state<=sh8out_bit5;
		 sh8out_buf<=sh8out_buf<<1;
       end
   else
       sh8out_state<=sh8out_bit6;
sh8out_bit5:
   if(!SCL)
      begin
      sh8out_state<=sh8out_bit4;
      sh8out_buf<=sh8out_buf<<1;
      end
   else
      sh8out_state<=sh8out_bit5;
sh8out_bit4:
   if(!SCL)
      begin
      sh8out_state<=sh8out_bit3;
      sh8out_buf<=sh8out_buf<<1;
      end
   else
      sh8out_state<=sh8out_bit4;
sh8out_bit3:
   if(!SCL)
     begin
       sh8out_state<=sh8out_bit2;
       sh8out_buf<=sh8out_buf<<1;
     end
   else
       sh8out_state<=sh8out_bit3;
sh8out_bit2:
   if(!SCL)
      begin
      sh8out_state<=sh8out_bit1;
      sh8out_buf<=sh8out_buf<<1;
      end
   else
      sh8out_state<=sh8out_bit2;
sh8out_bit1:
   if(!SCL)
       begin
       sh8out_state<=sh8out_bit0;
       sh8out_buf<=sh8out_buf<<1;
       end
   else
       sh8out_state<=sh8out_bit1;
sh8out_bit0:
   if(!SCL)
       begin
       sh8out_state<=sh8out_end;
       sh8out_buf<=sh8out_buf<<1;
       end
   else
       sh8out_state<=sh8out_bit0;
sh8out_end:
   if(!SCL)
       begin
       link_sda<=NO;
       link_write<=NO;FF<=1;
       end
   else
       sh8out_state<=sh8out_end;
endcase
end
endtask

//输出启动信号任务
task shift_head;
	begin
	casex(head_state)
	head_begin:
		if(!SCL)
			begin
			link_write<=NO;
			link_sda<=YES;
			link_head<=YES;
			head_state<=head_bit;
			end
		else
			head_state<=head_begin;
	head_bit:
		if(SCL)
			begin
			FF<=1;
			head_buf<=head_buf<<1;
			head_state<=head_end;
			end
		else
			head_state<=head_bit;
	head_end:
		if(!SCL)
			begin
			link_head<=NO;
			link_write<=YES;
			end
		else
			head_state<=head_end;
	endcase
	end
endtask
//输出停止信号任务
task shift_stop;
begin
casex(stop_state)
stop_begin:
   if(!SCL)
     begin
       link_sda<=YES;
       link_write<=NO;
       link_stop<=YES;
       stop_state<=stop_bit;
     end
   else
     stop_state<=stop_begin;
stop_bit:
   if(SCL)
     begin
       stop_buf<=stop_buf<<1;
       stop_state<=stop_end;
     end
   else
     stop_state<=stop_bit;
stop_end:
   if(!SCL)
     begin
       link_head<=NO;
       link_stop<=NO;
       link_sda<=NO;
       FF<=1;
     end
   else
     stop_state<=stop_end;
endcase
end
endtask
endmodule
//eeprom_wr.v文件结束
