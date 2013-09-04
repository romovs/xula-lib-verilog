# Before running `make' command make sure the ISE_BIN environment variable  
# points to ISE bin directory.

XST=		${ISE_BIN}/xst
NGDBUILD=	${ISE_BIN}/ngdbuild
MAP=		${ISE_BIN}/map
PAR=		${ISE_BIN}/par
BITGEN=		${ISE_BIN}/bitgen
TRCE=		${ISE_BIN}/trce

RTL=	    HostIo.v SdramCtrl.v Test.v Clk.v 

TARGET=		xc3s200a-4-vq100

TOP=		Test
UCF=		Test.ucf

all:    xst/fpga.bit
		cp xst/fpga.bit .

xst/fpga.bit:	xst/fpga.twr
		${BITGEN} -w -g StartupClk:JtagClk xst/fpga.ncd

xst/fpga.twr:	xst/fpga.par
		${TRCE} -v -fastpaths -o xst/fpga.twr xst/fpga.ncd xst/fpga.pcf -ucf ${UCF}

xst/fpga.par:	xst/fpga.ncd
		${PAR} -ol high -w xst/fpga.ncd xst/fpga.ncd

xst/fpga.ncd:	xst/fpga.ngd
		${MAP} -w  -p ${TARGET} -o xst/fpga.ncd xst/fpga.ngd

xst/fpga.ngd:	xst/fpga.ngc
		${NGDBUILD} -aul -uc ${UCF} xst/fpga.ngc xst/fpga.ngd

xst/fpga.ngc:	xst/fpga.xst
		${XST} ${INTSTYLE} -ifn xst/fpga.xst -ofn xst/fpga.srp

xst/fpga.xst:	xst/fpga.prj
		@echo "run"                 >  xst/fpga.xst
		@echo "-ifn xst/fpga.prj"	>> xst/fpga.xst
		@echo "-ifmt mixed"			>> xst/fpga.xst
		@echo "-top ${TOP}"			>> xst/fpga.xst
		@echo "-ofn xst/fpga.ngc"	>> xst/fpga.xst
		@echo "-ofmt NGC"			>> xst/fpga.xst
		@echo "-p ${TARGET}"		>> xst/fpga.xst
		@echo "-opt_mode speed"		>> xst/fpga.xst
		@echo "-opt_level 2"		>> xst/fpga.xst
		@echo "-tmpdir tmp"			>> xst/fpga.xst
		@echo "-xsthdpdir tmp"		>> xst/fpga.xst

xst/fpga.prj:	${RTL} ${UCF}
		mkdir -p xst
		rm -f xst/fpga.prj
		touch xst/fpga.prj
		@for f in ${RTL}; do echo "verilog work $$f" >> xst/fpga.prj; done

clean:
		rm -rf xst xlnx_auto_0_xdb _xmsgs
		rm -f *~ *.xrpt *.bit *.xml *.lst *.lso
		rm -rf */*~

