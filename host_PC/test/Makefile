CC = gcc
CFLAGS = -O2 -Wall

all: test

test: test.c
	$(CC) -o test test.c -Iinclude ../XstoolsLib/libxstoolsapi.so.5.1.3

clean:
	rm -f test test.o *~ 



