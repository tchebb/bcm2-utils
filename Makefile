CC ?= $(CROSS)gcc
CXX ?= $(CROSS)g++
STRIP = $(CROSS)strip
OBJCOPY = $(CROSS)objcopy
LIBS ?=
VERSION = $(shell git describe --always || cat version.txt)
CFLAGS += -Wall -Wno-sign-compare -g '-DVERSION="$(VERSION)"'
CXXFLAGS += $(CFLAGS) -std=c++14 -Wnon-virtual-dtor
PREFIX ?= /usr/local
SNMPLIB = -lsnmp

MIPS ?= mips-linux-gnu-

ifeq ($(OS),Windows_NT)
	CFLAGS += -D_WIN32_WINNT=_WIN32_WINNT_VISTA -Iinclude
	LDFLAGS += -lws2_32 -static-libstdc++ -static-libgcc
	BINEXT = .exe
	CC = gcc
else ifeq ($(shell uname),Darwin)
	CFLAGS +=
	SNMPLIB=-lnetsnmp
else
	bcm2cfg_LIBS += -lcrypto
endif

profile_OBJ = profile.o profiledef.o

bcm2dump_OBJ = io.o rwx.o interface.o ps.o bcm2dump.o \
	util.o progress.o $(profile_OBJ)
bcm2cfg_OBJ = util.o nonvol2.o bcm2cfg.o nonvoldef.o \
	gwsettings.o $(profile_OBJ) crypto.o
psextract_OBJ = util.o ps.o psextract.o
t_nonvol_OBJ = util.o nonvol2.o t_nonvol.o $(profile_OBJ)

ifeq ($(WITH_SNMP), 1)
	bcm2dump_OBJ += snmp.o
	CFLAGS += -DBCM2DUMP_WITH_SNMP
	LDFLAGS += $(SNMPLIB)
endif

bcm2dump = bcm2dump$(BINEXT)
bcm2cfg = bcm2cfg$(BINEXT)
psextract = psextract$(BINEXT)

define PackageRelease
	zip bcm2utils-$(VERSION)-$(1).zip README.md $(bcm2dump) $(bcm2cfg) $(psextract)
endef

.PHONY: all clean mrproper

all: $(bcm2dump) $(bcm2cfg) $(psextract)

release: clean all
	$(STRIP) bcm2cfg$(BINEXT) bcm2dump$(BINEXT) psextract$(BINEXT)

release-linux:
	LDFLAGS="-static-libstdc++ -static-libgcc" make release
	$(call PackageRelease,linux)

release-macos: release
	$(call PackageRelease,macos)

release-win32-extbuild:
	$(call PackageRelease,win32,.exe)

ifeq ($(MSYSTEM), MINGW32)
release-mingw32: release release-win32-extbuild
endif


$(bcm2cfg): $(bcm2cfg_OBJ)
	$(CXX) $(CXXFLAGS) $(bcm2cfg_OBJ) -o $@ $(bcm2cfg_LIBS) $(LDFLAGS)

$(bcm2dump): $(bcm2dump_OBJ)
	$(CXX) $(CXXFLAGS) $(bcm2dump_OBJ) -o $@ $(LDFLAGS)

$(psextract): $(psextract_OBJ)
	$(CXX) $(CXXFLAGS) $(psextract_OBJ) -o $@ $(LDFLAGS)

t_nonvol: $(t_nonvol_OBJ)
	$(CXX) $(CXXFLAGS) $(t_nonvol_OBJ) -o $@ $(LDFLAGS)

rwx.o: rwx.cc rwx.h rwcode2.h rwcode2.inc
	$(CXX) -c $(CXXFLAGS) $< -o $@

rwcode2.inc: rwcode2.c rwcode2.h
	$(MIPS)gcc -Wall -c -Os -ffreestanding -mips4 -ffunction-sections -mno-abicalls $< -o rwcode2.elf
	./bin2hdr.rb $(MIPS) rwcode2.elf > $@ || rm $@

%.o: %.c %.h
	$(CC) -c $(CFLAGS) $< -o $@

%.o: %.cc %.h
	$(CXX) -c $(CXXFLAGS) $< -o $@

%.inc: %.asm
	$(MIPS)gcc -c -x assembler-with-cpp $< -o $*.o
	$(MIPS)objcopy -j .text -O binary $*.o $*.bin
	echo "// Autogenerated from $*.asm, $(VERSION)" > $@
	./bin2hdr.rb defines $*.o >> $@
	./bin2hdr.rb code $*.bin >> $@

check: t_nonvol
	./t_nonvol

clean:
	rm -f t_nonvol $(bcm2cfg) $(bcm2dump) $(psextract) *.o

mrproper: clean
	rm -f *.inc

install: all
	install -m 755 $(bcm2cfg) $(PREFIX)/bin
	install -m 755 $(bcm2dump) $(PREFIX)/bin
	install -m 755 $(psextract) $(PREFIX)/bin
