#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#define USB_ID 0

int main(int argc,char **argv) {

	int i;

	unsigned int dut;
	unsigned int inVecWidth;
	unsigned int outVecWidth;
	unsigned char outputs[5];
	unsigned char inputs[4];

	unsigned int ram;
	unsigned int addrWidth; 
	unsigned int dataWidth; 
	int ramSize;


	printf("========================================================================\n");
	printf("Testing HostIoDut...\n");

	dut = XsDutInit(USB_ID, 1, &inVecWidth, &outVecWidth);		// initialize HostIoDut
	printf("Input vector width: %d\nOutput vector width: %d\n\n", inVecWidth, outVecWidth);

	for (i = 0; i < 9; i++) {
		XsDutWrite(dut, &inputs, inVecWidth); 			// pulse the counter clock input. the actual data we write here doesn't matter. 
		XsDutRead(dut, &outputs, outVecWidth); 			// read the new counter value
		printf("%d %d %d %d %d\n", outputs[4], outputs[3], outputs[2], outputs[1], outputs[0]); 
	}
	

	printf("========================================================================\n");
	printf("Test HostIoRam...\n");

	ram = XsMemInit(USB_ID, 3, &addrWidth, &dataWidth);	// initialize HostIoRam
	printf(" Addr Width: %d\n Data Width: %d\n\n", addrWidth, dataWidth);

	ramSize = 1 << addrWidth;
	ramSize /= 2;	// xula-200 exposes only 4mb of ram	

	unsigned long long *wData = (unsigned long long *)malloc(ramSize*sizeof(unsigned long long)); 
	unsigned long long *rData = (unsigned long long *)malloc(ramSize*sizeof(unsigned long long)); 


	int num = 2097152;		// number of 16bit words to write/read
	int addr = 0;			// starting address for writing/reading

	// generate some values for writing to the ram
	unsigned long k;
	for (k = 0; k < num; k++) {
		wData[k] = (unsigned short)k;
	}

	printf("Writing %d elements to SDRAM starting at %d...\n", num, addr);

	XsMemWrite(ram, addr, wData, num);


	printf("Reading %d elements from SDRAM starting at %d...\n", num, addr);

	for (k = 0; k < num; k++) {
		rData[k] = 0;
	}

	XsMemRead(ram, addr, rData, num); 

	/*for (k = 0; k < num; k++) {
		printf("%u ", rData[k]);
		if (k != 0 && k % 20 == 0)
			printf("\n");
	}*/

	// make sure the data we wrote to ram matches what we got back
	for (k = 0; k < num; k++) {
		if (rData[k] != wData[k]) {
			printf(" Oops, something went wrong! IN DATA != OUT DATA\n");
			free(rData);
			free(wData);
			return 1;
		}
	}


	sleep(4);

	// clear the input buffer
	for (k = 0; k < num; k++) {
		rData[k] = 0;
	}

	printf("Reading %d elements from SDRAM starting at %d...\n", num, addr);
	XsMemRead(ram, 0, rData, num); 

	// make sure the data we wrote to ram matches what we got back
	for (k = 0; k < num; k++) {
		if (rData[k] != wData[k]) {
			printf(" Oops, something went wrong! IN DATA != OUT DATA\n");
			free(rData);
			free(wData);
			return 1;
		}
	}

	printf("Done.\n", num, addr);
	

	free(rData);
	free(wData);
	return 0;
}

