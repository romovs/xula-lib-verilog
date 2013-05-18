#
# Makefile.in for the XClass library
#

top_srcdir=../
srcdir=.
prefix=/usr/local
exec_prefix=${prefix}
lib_dir=${prefix}/lib

lib_name=xstoolslib
lib_name_api=xstoolsapi

CXX=g++
INCLUDES=-I${srcdir}
DEFINES=
CXXFLAGS=${INCLUDES} ${DEFINES} -g -fPIC
EXTRALIBS=
EXTRALIBS_API=-L. -lxstoolslib -L/usr/local/lib -lusb
RANLIB=ranlib
AR=ar
INSTALL=/usr/bin/install -c
INSTALL_DATA=${INSTALL} -m 644

STATIC_LIB=lib${lib_name}.a
SHARED_LIB=lib${lib_name}.so.5.1.3
SO_NAME=lib${lib_name}.so.5.1.3

STATIC_LIB_API=lib${lib_name_api}.a
SHARED_LIB_API=lib${lib_name_api}.so.5.1.3
SO_NAME_API=lib${lib_name_api}.so.5.1.3

SRCS = BitBuffer.cpp \
	HostIo.cpp \
	HostIoToDut.cpp \
	HostIoToMemory.cpp \
	JtagPort.cpp \
	LibusbPort.cpp \
	UsbPort.cpp \
	XsAlloc.cpp \
	XsError.cpp

SRCS_API = XstoolsApi.cpp

OBJS=$(SRCS:.cpp=.o)
OBJS_API=$(SRCS_API:.cpp=.o)


#all: ${SHARED_LIB}
all: both

both: ${STATIC_LIB} ${SHARED_LIB} ${STATIC_LIB_API} ${SHARED_LIB_API}

shared: CXXFLAGS += -fPIC
shared: ${SHARED_LIB}

install: ${STATIC_LIB}
	${INSTALL_DATA} ${STATIC_LIB} ${lib_dir}

install_shared: ${SHARED_LIB}
	${INSTALL_DATA} ${SHARED_LIB} ${lib_dir}
	ldconfig

clean:
	rm -f ${OBJS} ${STATIC_LIB} ${SHARED_LIB} lib$(lib_name).so* *~ core *.bak
	rm -f ${OBJS_API} ${STATIC_LIB_API} ${SHARED_LIB_API} lib$(lib_name_api).so* *~ core *.bak

distclean: clean

depend: ${SRCS}
	makedepend -- ${CXXFLAGS} -- ${SRCS}

# Rules for compiling .cpp sources

.SUFFIX: .cpp .o
.cpp.o:
	$(CXX) $(CXXFLAGS) -c $<

# Rules for building the static library

${STATIC_LIB}: ${OBJS}
	${AR} cr ${STATIC_LIB} ${OBJS}
	${RANLIB} ${STATIC_LIB}

# Rules for building the shared library

${SHARED_LIB}: ${OBJS}
	g++ -shared -Wl,-soname,${SO_NAME} -o ${SHARED_LIB} $(OBJS) ${EXTRALIBS}



${STATIC_LIB_API}: ${OBJS_API}
	${AR} cr ${STATIC_LIB_API} ${OBJS_API}
	${RANLIB} ${STATIC_LIB_API}

# Rules for building the shared library

${SHARED_LIB_API}: ${OBJS_API}
	g++ -shared -Wl,-soname,${SO_NAME_API} -o ${SHARED_LIB_API} $(OBJS_API) ${EXTRALIBS_API}
