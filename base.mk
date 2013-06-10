## base.mk: d75a8ff, see https://github.com/jmesmon/trifles.git
# Usage:
#
# == For use by the one who runs 'make' (or in some cases the Makefile) ==
# $(V)              when defined, prints the commands that are run.
# $(CFLAGS)         expected to be overridden by the user or build system.
# $(LDFLAGS)        same as CFLAGS, except for LD.
# $(ASFLAGS)
# $(CXXFLAGS)
#
# $(CROSS_COMPILE)  a prefix on gcc. "CROSS_COMPILE=arm-linux-" (note the trailing '-')
# $(CC)
# $(CXX)
# $(LD)
# $(AS)
# $(FLEX)
# $(BISON)
#
# == Required in the makefile ==
# all::		    place this target at the top.
# $(obj-sometarget) the list of objects (generated by CC) that make up a target
#                   (in the list TARGET).
# $(TARGETS)        a list of binaries (the output of LD).
#
# == Optional (for use in the makefile) ==
# $(NO_INSTALL)     when defined, no install target is emitted.
# $(ALL_CFLAGS)     non-overriden flags. Append (+=) things that are absolutely
#                   required for the build to work into this.
# $(ALL_LDFLAGS)    same as ALL_CFLAGS, except for LD.
#		    example for adding some library:
#
#			sometarget: ALL_LDFLAGS += -lrt
#
#		    Note that in some cases (none I can point out, I just find
#		    this shifty) this usage could have unintended consequences
#		    (such as some of the ldflags being passed to other link
#		    commands). The use of $(ldflags-sometarget) is recommended
#		    instead.
#
# $(ldflags-sometarget)
# $(cflags-someobject)
# $(cxxflags-someobject)
#
# OBJ_TRASH		$(1) expands to the object. Expanded for every object.
# TARGET_TRASH		$* expands to the target. Expanded for every target.
# TRASH
# BIN_EXT
#
# == How to use with FLEX + BISON support ==
#
# obj-foo = name.tab.o name.ll.o
# name.ll.o : name.tab.h
# TRASH += name.ll.c name.tab.c name.tab.h
# # Optionally
# PP_name = not_quite_name_
#

# TODO:
# - install disable per target.
# - flag tracking per target.'.obj.o.cmd'
# - profile guided optimization support.
# - output directory support ("make O=blah")
# - build with different flags placed into different output directories.
# - library building (shared & static)
# - per-target CFLAGS (didn't I hack this in already?)
# - will TARGETS always be outputs from Linking?
# - continous build mechanism ('watch' is broken)

# Delete the default suffixes
.SUFFIXES:

O = .
BIN_TARGETS=$(addprefix $(O)/,$(addsuffix $(BIN_EXT),$(TARGETS)))

.PHONY: all FORCE
all:: $(BIN_TARGETS)

# FIXME: overriding these in a Makefile while still allowing the user to
# override them is tricky.
CC    = $(CROSS_COMPILE)gcc
CXX   = $(CROSS_COMPILE)g++
LD    = $(CC)
AS    = $(CC)
RM    = rm -f
FLEX  = flex
BISON = bison

ifdef DEBUG
OPT=-O0
else
OPT=-Os
endif

DBG_FLAGS = -ggdb3

ifndef NO_LTO
CFLAGS  ?= -flto $(DBG_FLAGS)
LDFLAGS ?= $(ALL_CFLAGS) $(OPT) -fuse-linker-plugin
else
CFLAGS  ?= $(OPT) $(DBG_FLAGS)
endif

COMMON_CFLAGS += -Wall
COMMON_CFLAGS += -Wundef -Wshadow
COMMON_CFLAGS += -pipe
COMMON_CFLAGS += -Wcast-align
COMMON_CFLAGS += -Wwrite-strings

# -Wnormalized=id		not supported by clang
# -Wunsafe-loop-optimizations	not supported by clang

ALL_CFLAGS += -std=gnu99
ALL_CFLAGS += -Wbad-function-cast
ALL_CFLAGS += -Wstrict-prototypes -Wmissing-prototypes

ALL_CFLAGS   += $(COMMON_CFLAGS) $(CFLAGS)
ALL_CXXFLAGS += $(COMMON_CFLAGS) $(CXXFLAGS)

ALL_LDFLAGS += -Wl,--build-id
ALL_LDFLAGS += -Wl,--as-needed
ALL_LDFLAGS += $(LDFLAGS)

ALL_ASFLAGS += $(ASFLAGS)

ifndef V
	QUIET_CC    = @ echo '  CC   ' $@;
	QUIET_CXX   = @ echo '  CXX  ' $@;
	QUIET_LINK  = @ echo '  LINK ' $@;
	QUIET_LSS   = @ echo '  LSS  ' $@;
	QUIET_SYM   = @ echo '  SYM  ' $@;
	QUIET_FLEX  = @ echo '  FLEX ' $@;
	QUIET_BISON = @ echo '  BISON' $*.tab.c $*.tab.h;
	QUIET_AS    = @ echo '  AS   ' $@;
endif

# Avoid deleting .o files
.SECONDARY:

obj-to-dep = $(foreach obj,$(1),$(dir $(obj)).$(notdir $(obj)).d)
target-dep = $(addprefix $(O)/,$(call obj-to-dep,$(obj-$(1))))
target-obj = $(addprefix $(O)/,$(obj-$(1)))

# flags-template flag-prefix vars message
# Defines a target '.TRACK-$(flag-prefix)FLAGS'.
# if $(ALL_$(flag-prefix)FLAGS) or $(var) changes, any rules depending on this
# target are rebuilt.
vpath .TRACK_%FLAGS $(O)
define flags-template
TRACK_$(1)FLAGS = $$($(2)):$$(subst ','\'',$$(ALL_$(1)FLAGS))
$(O)/.TRACK-$(1)FLAGS: FORCE
	@FLAGS='$$(TRACK_$(1)FLAGS)'; \
	if test x"$$$$FLAGS" != x"`cat $(O)/.TRACK-$(1)FLAGS 2>/dev/null`" ; then \
		echo 1>&2 "    * new $(3)"; \
		echo "$$$$FLAGS" >$(O)/.TRACK-$(1)FLAGS; \
	fi
TRASH += $(O)/.TRACK-$(1)FLAGS
endef

$(eval $(call flags-template,AS,AS,assembler build flags))
$(eval $(call flags-template,C,CC,c build flags))
$(eval $(call flags-template,CXX,CXX,c++ build flags))
$(eval $(call flags-template,LD,LD,link flags))

parser-prefix = $(if $(PP_$*),$(PP_$*),$*_)

$(O)/%.tab.h $(O)/%.tab.c : %.y
	$(QUIET_BISON)$(BISON) --locations -d \
		-p '$(parser-prefix)' -k -b $* $<

$(O)/%.ll.c : %.l
	$(QUIET_FLEX)$(FLEX) -P '$(parser-prefix)' --bison-locations --bison-bridge -o $@ $<

$(O)/%.o: %.c $(O)/.TRACK-CFLAGS
	$(QUIET_CC)$(CC)   -MMD -MF $(call obj-to-dep,$@) -c -o $@ $< $(ALL_CFLAGS) $(cflags-$*)

$(O)/%.o: %.cc $(O)/.TRACK-CXXFLAGS
	$(QUIET_CXX)$(CXX) -MMD -MF $(call obj-to-dep,$@) -c -o $@ $< $(ALL_CXXFLAGS) $(cxxflags-$*)

$(O)/%.o : %.S $(O)/.TRACK-ASFLAGS
	$(QUIET_AS)$(AS) -c $(ALL_ASFLAGS) $< -o $@

define BIN-LINK
$(O)/$(1)$(BIN_EXT) : $(O)/.TRACK-LDFLAGS $(call target-obj,$(1))
	$$(QUIET_LINK)$(LD) -o $$@ $(call target-obj,$(1)) $(ALL_LDFLAGS) $(ldflags-$(1))
endef

$(foreach target,$(TARGETS),$(eval $(call BIN-LINK,$(target))))

ifndef NO_INSTALL
PREFIX  ?= $(HOME)   # link against things here
DESTDIR ?= $(PREFIX) # install into here
BINDIR  ?= $(DESTDIR)/bin
.PHONY: install %.install
%.install: %
	install $* $(BINDIR)/$*
install: $(foreach target,$(TARGETS),$(target).install)
endif

obj-all = $(foreach target,$(TARGETS),$(obj-$(target)))
obj-trash = $(foreach obj,$(obj-all),$(call OBJ_TRASH,$(obj)))

.PHONY: clean %.clean
%.clean :
	$(RM) $(call target-obj,$*) $(O)/$* $(TARGET_TRASH) $(call target-dep,$*)

clean:	$(addsuffix .clean,$(TARGETS))
	$(RM) $(TRASH) $(obj-trash)

.PHONY: watch
watch:
	@while true; do \
		echo $(MAKEFLAGS); \
		$(MAKE) $(MAKEFLAGS) -rR --no-print-directory; \
		inotifywait -q \
		  \
		 -- $$(find . \
		        -name '*.c' \
			-or -name '*.h' \
			-or -name 'Makefile' \
			-or -name '*.mk' ); \
		echo "Rebuilding...";	\
	done

.PHONY: show-targets
show-targets:
	@echo $(TARGETS)

.PHONY: show-cflags
show-cflags:
	@echo $(ALL_CFLAGS) $(cflags-$(FILE:.c=))

deps = $(foreach target,$(TARGETS),$(call target-dep,$(target)))
-include $(deps)
