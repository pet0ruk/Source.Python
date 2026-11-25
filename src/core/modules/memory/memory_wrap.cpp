/**
* =============================================================================
* Source Python
* Copyright (C) 2012-2015 Source Python Development Team.  All rights reserved.
* =============================================================================
*
* This program is free software; you can redistribute it and/or modify it under
* the terms of the GNU General Public License, version 3.0, as published by the
* Free Software Foundation.
*
* This program is distributed in the hope that it will be useful, but WITHOUT
* ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
* FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
* details.
*
* You should have received a copy of the GNU General Public License along with
* this program.  If not, see <http://www.gnu.org/licenses/>.
*
* As a special exception, the Source Python Team gives you permission
* to link the code of this program (as well as its derivative works) to
* "Half-Life 2," the "Source Engine," and any Game MODs that run on software
* by the Valve Corporation.  You must obey the GNU General Public License in
* all respects for all other code used.  Additionally, the Source.Python
* Development Team grants this exception to all derivative works.
*/

// ============================================================================
// >> INCLUDES
// ============================================================================
#include "export_main.h"

// Memory
#include "memory_scanner.h"
#include "memory_tools.h"
#include "memory_hooks.h"
#include "memory_function_info.h"
#include "memory_utilities.h"
#include "memory_wrap.h"
#include "memory_rtti.h"

// DynamicHooks
#include "registers.h"

// ============================================================================
// >> FORWARD DECLARATIONS
// ============================================================================
void export_function_info(scope);
void export_binary_file(scope);
void export_pointer(scope);
void export_type_info(scope);
void export_type_info_iter(scope);
void export_function(scope);
void export_data_type_t(scope);
void export_convention_t(scope);
void export_hook_type_t(scope);
void export_stack_data(scope);
void export_register_t(scope);
void export_register(scope);
void export_registers(scope);
void export_calling_convention(scope);
void export_functions(scope);
void export_global_variables(scope);
void export_protection(scope);


// ============================================================================
// >> Exports the _memory module
// ============================================================================
DECLARE_SP_MODULE(_memory)
{
	SetHooksDisabled(false);

	export_function_info(_memory);
	export_binary_file(_memory);
	export_pointer(_memory);
	export_type_info(_memory);
	export_type_info_iter(_memory);
	export_function(_memory);
	export_data_type_t(_memory);
	export_convention_t(_memory);
	export_hook_type_t(_memory);
	export_stack_data(_memory);
	export_register_t(_memory);
	export_register(_memory);
	export_registers(_memory);
	export_calling_convention(_memory);
	export_functions(_memory);
	export_global_variables(_memory);
	export_protection(_memory);
}


// ============================================================================
// >> CFunctionInfo
// ============================================================================
void export_function_info(scope _core)
{
	class_<CFunctionInfo> _FunctionInfo("FunctionInfo", no_init);

	_FunctionInfo.def_readonly("is_virtual", &CFunctionInfo::m_bIsVirtual);
	_FunctionInfo.def_readonly("this_pointer_offset", &CFunctionInfo::m_iThisPtrOffset);
	_FunctionInfo.def_readonly("vtable_index", &CFunctionInfo::m_iVtableIndex);
	_FunctionInfo.def_readonly("vtable_offset", &CFunctionInfo::m_iVtableOffset);
	_FunctionInfo.def_readonly("return_type", &CFunctionInfo::m_eReturnType);
	_FunctionInfo.add_property("argument_types", &CFunctionInfo::GetArgumentTypes);
	_FunctionInfo.def_readonly("calling_convention", &CFunctionInfo::m_eCallingConvention);
}


// ============================================================================
// >> CBinaryFile
// ============================================================================
void export_binary_file(scope _memory)
{
	class_<CBinaryFile, boost::noncopyable>("BinaryFile", no_init)

		// Class methods
		.def("find_pointer",
			&CBinaryFile::FindPointer,
			"Rips out a pointer from a function.",
			("signature", arg("offset")=0, arg("level")=0),
			manage_new_object_policy()
		)

		.def("find_address",
			&CBinaryFile::FindAddress,
			"Returns the address of a signature or symbol found in memory.",
			args("identifier"),
			manage_new_object_policy()
		)

		// Special methods
		.def("__getitem__",
			&CBinaryFile::FindAddress,
			"Returns the address of a signature or symbol found in memory.",
			args("identifier"),
			manage_new_object_policy()
		)
	
		// Attributes
		.def_readwrite("module",
			&CBinaryFile::m_ulModule,
			"Handle of the binary."
		)

		.def_readwrite("base",
			&CBinaryFile::m_ulBase,
			"Base address of the binary."
		)

		.def_readwrite("size",
			&CBinaryFile::m_ulSize,
			"Size of the binary."
		)

		.add_property("symbols",
			&CBinaryFile::GetSymbols,
			"Return a dict containing all symbols and their addresses."
		)
	;
}


// ============================================================================
// >> CPointer
// ============================================================================
#define EXPOSE_SET_TYPE(name, type) \
	.def("set_" XSTRINGIFY(name), \
		&CPointer::Set<type>, \
		"Sets the value at the given memory location.", \
		("value", arg("offset")=0) \
	)

#define EXPOSE_GET_TYPE(name, type) \
	.def("get_" XSTRINGIFY(name), \
		&CPointer::Get<type>, \
		"Returns the value at the given memory location.", \
		(arg("offset")=0) \
	)

#define EXPOSE_GET_SET_TYPE(name, type) \
	EXPOSE_SET_TYPE(name, type) \
	EXPOSE_GET_TYPE(name, type)

void export_pointer(scope _memory)
{
	class_<CPointer, boost::shared_ptr<CPointer> >("Pointer", init< optional<uintptr_t, bool> >())
		.def(init<CPointer&>())

		// get/set_<type> methods
		EXPOSE_GET_SET_TYPE(bool, bool)
		EXPOSE_GET_SET_TYPE(char, char)
		EXPOSE_GET_SET_TYPE(uchar, unsigned char)
		EXPOSE_GET_SET_TYPE(short, short)
		EXPOSE_GET_SET_TYPE(ushort, unsigned short)
		EXPOSE_GET_SET_TYPE(int, int)
		EXPOSE_GET_SET_TYPE(uint, unsigned int)
		EXPOSE_GET_SET_TYPE(long, long)
		EXPOSE_GET_SET_TYPE(ulong, unsigned long)
		EXPOSE_GET_SET_TYPE(long_long, long long)
		EXPOSE_GET_SET_TYPE(ulong_long, unsigned long long)
		EXPOSE_GET_SET_TYPE(float, float)
		EXPOSE_GET_SET_TYPE(double, double)
		EXPOSE_GET_TYPE(string_pointer, const char*)

		.def("set_string_pointer",
			&CPointer::SetStringPointer,
			"Sets the value at the given memory location to a pointer to a copy of the string. "
			"The copy stays valid until the server exits (and is shared by equal strings), so "
			"the memory never points at freed Python data; every distinct string written is kept.",
			("value", arg("offset")=0)
		)

		.def("get_pointer",
			&CPointer::GetPtr,
			"Returns the value at the given memory location.",
			(arg("offset")=0),
			manage_new_object_policy()
		)

		.def("get_string_array",
			&CPointer::GetStringArray,
			"Returns the value at the memory location.",
			(arg("offset")=0)
		)
		
		.def("set_pointer",
			&CPointer::SetPtr,
			"Sets the value at the given memory location.",
			("value", arg("offset")=0)
		)

		.def("set_string_array",
			&CPointer::SetStringArray,
			"Sets the value at the given memory location.",
			("value",arg( "offset")=0)
		)

		// Other methods
		.def("get_virtual_func",
			&CPointer::GetVirtualFunc,
			"Returns the address (as a Pointer instance) of a virtual function at the given index.",
			args("index"),
			manage_new_object_policy()
		)

		.def("make_function",
			GET_METHOD(CFunction*, CPointer, MakeFunction, object, object, object),
			"Creates a new Function instance.",
			args("convention", "arguments", "return_type"),
			manage_new_object_policy()
		)

		.def("make_function",
			GET_METHOD(CFunction*, CPointer, MakeFunction, CFunctionInfo&),
			"Use the given FunctionInfo object to convert the pointer into a Function object.",
			("info"),
			manage_new_object_policy()
		)

		.def("make_virtual_function",
			GET_METHOD(CFunction*, CPointer, MakeVirtualFunction, int, object, object, object),
			"Creates a new Function instance.",
			args("index", "convention", "arguments", "return_type"),
			manage_new_object_policy()
		)

		.def("make_virtual_function",
			GET_METHOD(CFunction*, CPointer, MakeVirtualFunction, CFunctionInfo&),
			"Use the given FunctionInfo object to retrieve a virtual function and convert it into a Function object.",
			("info"),
			manage_new_object_policy()
		)

		.def("realloc",
			&CPointer::PreRealloc,
			"Reallocates a memory block.",
			args("size"),
			manage_new_object_policy()
		)

		.def("dealloc",
			&CPointer::PreDealloc,
			"Deallocates a memory block."
		)

		.def("__del__",
			&CPointer::__del__
		)

		 .add_property("size",
			&CPointer::GetSize,
			"Returns the size of the memory block."
		)

		.def("compare",
			&CPointer::Compare,
			"Compares the first <num> bytes of both pointers. Returns 0 if they are equal. A value greater than zero indicates that the first "\
			"byte that does not match in both pointers has a greater value in <self> than in <other>. A value less than zero indicates the opposite.",
			args("other", "num")
		)

		.def("is_overlapping",
			&CPointer::IsOverlapping,
			"Returns True if the pointers are overlapping each other.",
			args("destination", "num_bytes")
		)

		.def("search_bytes",
			&CPointer::SearchBytes,
			"Searches within the first <num_bytes> of this memory block for the first occurence of <bytes> and returns a pointer it.",
			args("bytes", "num_bytes"),
			manage_new_object_policy()
		)

		.def("copy",
			&CPointer::Copy,
			"Copies <num_bytes> from <self> to the pointer <destination>. Overlapping is not allowed!",
			args("destination", "num_bytes")
		)

		.def("move",
			&CPointer::Move,
			"Copies <num_bytes> from <self> to the pointer <destination>. Overlapping is allowed!",
			args("destination", "num_bytes")
		)

		.def("set_protection",
			&CPointer::SetProtection,
			"Set memory protection.",
			args("protection", "size")
		)

		.def("protect",
			&CPointer::Protect,
			"Make the memory block read-only.",
			args("size")
		)

		.def("unprotect",
			&CPointer::UnProtect,
			"Make the memory block read-, write- and executable.",
			args("size")
		)

		// Special methods
		.def("__int__", make_getter(&CPointer::m_ulAddr))

        .def(!self)

        .def(self == other<uintptr_t>())
        .def(self == self)

        .def(self != other<uintptr_t>())
        .def(self != self)

        .def(self += int())
        .def(self += self)

        .def(self < other<uintptr_t>())
        .def(self < self)

        .def(self <= other<uintptr_t>())
        .def(self <= self)

        .def(self > other<uintptr_t>())
        .def(self > self)

        .def(self >= other<uintptr_t>())
        .def(self >= self)
		
        .def("__add__", &CPointer::operator+<uintptr_t>, manage_new_object_policy())
        .def("__add__", &CPointer::operator+<CPointer>, manage_new_object_policy())

        .def("__radd__", &CPointer::operator+<uintptr_t>, manage_new_object_policy())
        .def("__radd__", &CPointer::operator+<CPointer>, manage_new_object_policy())

        .def(self -= int())
        .def(self -= self)
		
        .def("__sub__", &CPointer::operator-<uintptr_t>, manage_new_object_policy())
        .def("__sub__", &CPointer::operator-<CPointer>, manage_new_object_policy())

        .def("__rsub__", &CPointer::operator-<uintptr_t>, manage_new_object_policy())
        .def("__rsub__", &CPointer::operator-<CPointer>, manage_new_object_policy())

		// Attributes
		.def_readwrite("address", 
			&CPointer::m_ulAddr
		)

		.def_readwrite("auto_dealloc",
			&CPointer::m_bAutoDealloc
		)

		// Properties
		.add_property("type_info",
			make_function(&CPointer::GetTypeInfo, manage_new_object_policy())
		)
	;
}


// ============================================================================
// >> IBaseType
// ============================================================================
void export_type_info(scope _memory)
{
	class_<IBaseType, boost::noncopyable> TypeInfo("TypeInfo", no_init);

	TypeInfo.add_property(
		"name",
		&IBaseType::GetName,
		"Return the class name of the type."
	);

	TypeInfo.def(
		"is_derived_from",
		GET_METHOD(bool, IBaseType, IsDerivedFrom, const char*),
		"Return True if the type is derived from the given class name."
	);

	TypeInfo.def(
		"is_derived_from", 
		GET_METHOD(bool, IBaseType, IsDerivedFrom, IBaseType*),
		"Return True if the type is derived from the given class name."
	);

	TypeInfo.def(
		"__iter__", 
		&IBaseTypeExt::__iter__, 
		manage_new_object_policy(),
		"Return an iterator to iterate over all base classes."
	);

	TypeInfo.def(
		"dump",
		GET_METHOD(void, IBaseType, Dump),
		"Dump the class hierachy to the console."
	);
}


// ============================================================================
// >> IBaseTypeIter
// ============================================================================
void export_type_info_iter(scope _memory)
{
	class_<IBaseTypeIter> _IBaseTypeIter("TypeInfoIter", init<IBaseType*>());

	_IBaseTypeIter.def(
		"__next__",
		&IBaseTypeIter::__next__,
		reference_existing_object_policy()
	);
}


// ============================================================================
// >> CFunction
// ============================================================================
void export_function(scope _memory)
{
	class_<CFunction, bases<CPointer> >("Function", init<uintptr_t, object, object, object>())
		.def(init<CFunction&>())

		.def("__call__",
			very_raw_method(&CFunction::Call),
			"Calls the function dynamically."
		)

		.def("is_callable",
			&CFunction::IsCallable,
			"Return True if the function is callable."
		)

		.def("is_hookable",
			&CFunction::IsHookable,
			"Return True if the function is hookable."
		)

		.def("is_hooked",
			&CFunction::IsHooked,
			"Return True if the function is hooked."
		)

		.def("call_trampoline",
			very_raw_method(&CFunction::CallTrampoline),
			"Calls the trampoline function dynamically."
		)

		.def("skip_hooks",
			very_raw_method(&CFunction::SkipHooks),
			"Call the function, but skip hooks if there are any."
		)

		.def("add_hook",
			GET_METHOD(void, CFunction, AddHook, HookType_t eType, PyObject*),
			"Adds a hook callback.",
			args("hook_type", "callback")
		)

		.def("remove_hook",
			&CFunction::RemoveHook,
			"Removes a hook callback.",
			args("hook_type", "callback")
		)

		.def("add_pre_hook",
			&CFunction::AddPreHook,
			"Adds a pre-hook callback."
		)

		.def("add_post_hook",
			&CFunction::AddPostHook,
			"Adds a post-hook callback."
		)

		.def("remove_pre_hook",
			&CFunction::RemovePreHook,
			"Removes a pre-hook callback."
		)

		.def("remove_post_hook",
			&CFunction::RemovePostHook,
			"Removes a post-hook callback."
		)

		.def("_delete_hook",
			&CFunction::DeleteHook,
			"Removes all hooks and restores the original function."
		)

		// Attributes
		.def_readonly("arguments",
			&CFunction::m_tArgs
		)

		.def_readonly("return_type",
			&CFunction::m_eReturnType
		)

		.def_readonly("converter",
			&CFunction::m_oConverter
		)

		.def_readonly("convention",
			&CFunction::m_eCallingConvention
		)

		.def_readonly("custom_convention",
			&CFunction::m_oCallingConvention
		)

		// Properties
		.add_property("trampoline",
			make_function(&CFunction::GetTrampoline, manage_new_object_policy()),
			"Return the trampoline function if the function is hooked."
		)
	;
}


// ============================================================================
// >> DataType_t
// ============================================================================
void export_data_type_t(scope _memory)
{
	enum_<DataType_t>("DataType")
		.value("VOID", DATA_TYPE_VOID)
		.value("BOOL", DATA_TYPE_BOOL)
		.value("CHAR", DATA_TYPE_CHAR)
		.value("UCHAR", DATA_TYPE_UCHAR)
		.value("SHORT", DATA_TYPE_SHORT)
		.value("USHORT", DATA_TYPE_USHORT)
		.value("INT", DATA_TYPE_INT)
		.value("UINT", DATA_TYPE_UINT)
		.value("LONG", DATA_TYPE_LONG)
		.value("ULONG", DATA_TYPE_ULONG)
		.value("LONG_LONG", DATA_TYPE_LONG_LONG)
		.value("ULONG_LONG", DATA_TYPE_ULONG_LONG)
		.value("FLOAT", DATA_TYPE_FLOAT)
		.value("DOUBLE", DATA_TYPE_DOUBLE)
		.value("POINTER", DATA_TYPE_POINTER)
		.value("STRING", DATA_TYPE_STRING)
	;
}


// ============================================================================
// >> Convention_t
// ============================================================================
void export_convention_t(scope _memory)
{
	enum_<Convention_t>("Convention")
		.value("CUSTOM", CONV_CUSTOM)
		.value("CDECL", CONV_CDECL)
		.value("STDCALL", CONV_STDCALL)
		.value("THISCALL", CONV_THISCALL)
		.value("FASTCALL", CONV_FASTCALL)
	;
}


// ============================================================================
// >> HookType_t
// ============================================================================
void export_hook_type_t(scope _memory)
{
	enum_<HookType_t>("HookType")
		.value("PRE", HOOKTYPE_PRE)
		.value("POST", HOOKTYPE_POST)
	;
}


// ============================================================================
// >> CStackData
// ============================================================================
void export_stack_data(scope _memory)
{
	class_<CStackData>("StackData", init<CHook*>())
		// Special methods
		.def("__getitem__",
			&CStackData::GetItem,
			"Returns the argument at the specified index."
		)

		.def("__setitem__",
			&CStackData::SetItem,
			"Sets the argument at the specified index."
		)

		.add_property("return_address",
			make_function(&CStackData::GetReturnAddress, return_by_value_policy()),
			"Return the 'return address' to which DynamicHooks will jump after the post-hook has finished."
		)

		.def("__repr__",
			&CStackData::__repr__
		)

		.add_property("registers",
			make_function(&CStackData::GetRegisters, reference_existing_object_policy())
		)

		.add_property(
			"use_pre_registers",
			&CStackData::GetUsePreRegister,
			&CStackData::SetUsePreRegisters)
	;
}


// ============================================================================
// >> Register_t
// ============================================================================
void export_register_t(scope _memory)
{
	enum_<Register_t>("Register")
		// ========================================================================
		// >> 8-bit General purpose registers
		// ========================================================================
		.value("AL", AL)
		.value("CL", CL)
		.value("DL", DL)
		.value("BL", BL)

		.value("AH", AH)
		.value("CH", CH)
		.value("DH", DH)
		.value("BH", BH)

		// ========================================================================
		// >> 16-bit General purpose registers
		// ========================================================================
		.value("AX", AX)
		.value("CX", CX)
		.value("DX", DX)
		.value("BX", BX)
		.value("SP", SP)
		.value("BP", BP)
		.value("SI", SI)
		.value("DI", DI)

		// ========================================================================
		// >> 32-bit General purpose registers
		// ========================================================================
		.value("EAX", EAX)
		.value("ECX", ECX)
		.value("EDX", EDX)
		.value("EBX", EBX)
		.value("ESP", ESP)
		.value("EBP", EBP)
		.value("ESI", ESI)
		.value("EDI", EDI)

		// ========================================================================
		// >> 64-bit MM (MMX) registers
		// ========================================================================
		.value("MM0", MM0)
		.value("MM1", MM1)
		.value("MM2", MM2)
		.value("MM3", MM3)
		.value("MM4", MM4)
		.value("MM5", MM5)
		.value("MM6", MM6)
		.value("MM7", MM7)

		// ========================================================================
		// >> 128-bit XMM registers
		// ========================================================================
		.value("XMM0", XMM0)
		.value("XMM1", XMM1)
		.value("XMM2", XMM2)
		.value("XMM3", XMM3)
		.value("XMM4", XMM4)
		.value("XMM5", XMM5)
		.value("XMM6", XMM6)
		.value("XMM7", XMM7)

		// ========================================================================
		// >> 16-bit Segment registers
		// ========================================================================
		.value("CS", CS)
		.value("SS", SS)
		.value("DS", DS)
		.value("ES", ES)
		.value("FS", FS)
		.value("GS", GS)

		// ========================================================================
		// >> 80-bit FPU registers
		// ========================================================================
		.value("ST0", ST0)

#ifdef DYNAMICHOOKS_X86_64
		// x86-64 only
		.value("RAX", RAX)
		.value("RCX", RCX)
		.value("RDX", RDX)
		.value("RBX", RBX)
		.value("RSP", RSP)
		.value("RBP", RBP)
		.value("RSI", RSI)
		.value("RDI", RDI)
		.value("R8", R8)
		.value("R9", R9)
		.value("R10", R10)
		.value("R11", R11)
		.value("R12", R12)
		.value("R13", R13)
		.value("R14", R14)
		.value("R15", R15)
		.value("XMM8", XMM8)
		.value("XMM9", XMM9)
		.value("XMM10", XMM10)
		.value("XMM11", XMM11)
		.value("XMM12", XMM12)
		.value("XMM13", XMM13)
		.value("XMM14", XMM14)
		.value("XMM15", XMM15)
#endif
		// The following registers are currently not supported by DynamicHooks
		/*
		.value("ST1", ST1)
		.value("ST2", ST2)
		.value("ST3", ST3)
		.value("ST4", ST4)
		.value("ST5", ST5)
		.value("ST6", ST6)
		.value("ST7", ST7)
		*/
	;
}


// ============================================================================
// >> CRegister
// ============================================================================
void export_register(scope _memory)
{
	class_<CRegister, CRegister*, boost::noncopyable>("ProcessorRegister", no_init)
		.add_property("size",
			&CRegister::GetSize
		)

		.add_property("address",
			make_function(&CRegisterExt::GetAddress, manage_new_object_policy())
		)
	;
}


// ============================================================================
// >> CRegisters
// ============================================================================
void export_registers(scope _memory)
{
	class_<CRegisters, boost::noncopyable>("Registers", no_init)
		.add_property("al", make_function(&GetRegister<AL>, reference_existing_object_policy()))
		.add_property("cl", make_function(&GetRegister<CL>, reference_existing_object_policy()))
		.add_property("dl", make_function(&GetRegister<DL>, reference_existing_object_policy()))
		.add_property("bl", make_function(&GetRegister<BL>, reference_existing_object_policy()))

		.add_property("ah", make_function(&GetRegister<AH>, reference_existing_object_policy()))
		.add_property("ch", make_function(&GetRegister<CH>, reference_existing_object_policy()))
		.add_property("dh", make_function(&GetRegister<DH>, reference_existing_object_policy()))
		.add_property("bh", make_function(&GetRegister<BH>, reference_existing_object_policy()))
		
		.add_property("ax", make_function(&GetRegister<AX>, reference_existing_object_policy()))
		.add_property("cx", make_function(&GetRegister<CX>, reference_existing_object_policy()))
		.add_property("dx", make_function(&GetRegister<DX>, reference_existing_object_policy()))
		.add_property("bx", make_function(&GetRegister<BX>, reference_existing_object_policy()))
		.add_property("sp", make_function(&GetRegister<SP>, reference_existing_object_policy()))
		.add_property("bp", make_function(&GetRegister<BP>, reference_existing_object_policy()))
		.add_property("si", make_function(&GetRegister<SI>, reference_existing_object_policy()))
		.add_property("di", make_function(&GetRegister<DI>, reference_existing_object_policy()))
		
		.add_property("eax", make_function(&GetRegister<EAX>, reference_existing_object_policy()))
		.add_property("ecx", make_function(&GetRegister<ECX>, reference_existing_object_policy()))
		.add_property("edx", make_function(&GetRegister<EDX>, reference_existing_object_policy()))
		.add_property("ebx", make_function(&GetRegister<EBX>, reference_existing_object_policy()))
		.add_property("esp", make_function(&GetRegister<ESP>, reference_existing_object_policy()))
		.add_property("ebp", make_function(&GetRegister<EBP>, reference_existing_object_policy()))
		.add_property("esi", make_function(&GetRegister<ESI>, reference_existing_object_policy()))
		.add_property("edi", make_function(&GetRegister<EDI>, reference_existing_object_policy()))
		
		.add_property("mm0", make_function(&GetRegister<MM0>, reference_existing_object_policy()))
		.add_property("mm1", make_function(&GetRegister<MM1>, reference_existing_object_policy()))
		.add_property("mm2", make_function(&GetRegister<MM2>, reference_existing_object_policy()))
		.add_property("mm3", make_function(&GetRegister<MM3>, reference_existing_object_policy()))
		.add_property("mm4", make_function(&GetRegister<MM4>, reference_existing_object_policy()))
		.add_property("mm5", make_function(&GetRegister<MM5>, reference_existing_object_policy()))
		.add_property("mm6", make_function(&GetRegister<MM6>, reference_existing_object_policy()))
		.add_property("mm7", make_function(&GetRegister<MM7>, reference_existing_object_policy()))
		
		.add_property("xmm0", make_function(&GetRegister<XMM0>, reference_existing_object_policy()))
		.add_property("xmm1", make_function(&GetRegister<XMM1>, reference_existing_object_policy()))
		.add_property("xmm2", make_function(&GetRegister<XMM2>, reference_existing_object_policy()))
		.add_property("xmm3", make_function(&GetRegister<XMM3>, reference_existing_object_policy()))
		.add_property("xmm4", make_function(&GetRegister<XMM4>, reference_existing_object_policy()))
		.add_property("xmm5", make_function(&GetRegister<XMM5>, reference_existing_object_policy()))
		.add_property("xmm6", make_function(&GetRegister<XMM6>, reference_existing_object_policy()))
		.add_property("xmm7", make_function(&GetRegister<XMM7>, reference_existing_object_policy()))
		
		.add_property("cs", make_function(&GetRegister<CS>, reference_existing_object_policy()))
		.add_property("ss", make_function(&GetRegister<SS>, reference_existing_object_policy()))
		.add_property("ds", make_function(&GetRegister<DS>, reference_existing_object_policy()))
		.add_property("es", make_function(&GetRegister<ES>, reference_existing_object_policy()))
		.add_property("fs", make_function(&GetRegister<FS>, reference_existing_object_policy()))
		.add_property("gs", make_function(&GetRegister<GS>, reference_existing_object_policy()))
		
		.add_property("st0", make_function(&GetRegister<ST0>, reference_existing_object_policy()))

#ifdef DYNAMICHOOKS_X86_64
		// x86-64 only
		.add_property("rax", make_function(&GetRegister<RAX>, reference_existing_object_policy()))
		.add_property("rcx", make_function(&GetRegister<RCX>, reference_existing_object_policy()))
		.add_property("rdx", make_function(&GetRegister<RDX>, reference_existing_object_policy()))
		.add_property("rbx", make_function(&GetRegister<RBX>, reference_existing_object_policy()))
		.add_property("rsp", make_function(&GetRegister<RSP>, reference_existing_object_policy()))
		.add_property("rbp", make_function(&GetRegister<RBP>, reference_existing_object_policy()))
		.add_property("rsi", make_function(&GetRegister<RSI>, reference_existing_object_policy()))
		.add_property("rdi", make_function(&GetRegister<RDI>, reference_existing_object_policy()))
		.add_property("r8", make_function(&GetRegister<R8>, reference_existing_object_policy()))
		.add_property("r9", make_function(&GetRegister<R9>, reference_existing_object_policy()))
		.add_property("r10", make_function(&GetRegister<R10>, reference_existing_object_policy()))
		.add_property("r11", make_function(&GetRegister<R11>, reference_existing_object_policy()))
		.add_property("r12", make_function(&GetRegister<R12>, reference_existing_object_policy()))
		.add_property("r13", make_function(&GetRegister<R13>, reference_existing_object_policy()))
		.add_property("r14", make_function(&GetRegister<R14>, reference_existing_object_policy()))
		.add_property("r15", make_function(&GetRegister<R15>, reference_existing_object_policy()))
		.add_property("xmm8", make_function(&GetRegister<XMM8>, reference_existing_object_policy()))
		.add_property("xmm9", make_function(&GetRegister<XMM9>, reference_existing_object_policy()))
		.add_property("xmm10", make_function(&GetRegister<XMM10>, reference_existing_object_policy()))
		.add_property("xmm11", make_function(&GetRegister<XMM11>, reference_existing_object_policy()))
		.add_property("xmm12", make_function(&GetRegister<XMM12>, reference_existing_object_policy()))
		.add_property("xmm13", make_function(&GetRegister<XMM13>, reference_existing_object_policy()))
		.add_property("xmm14", make_function(&GetRegister<XMM14>, reference_existing_object_policy()))
		.add_property("xmm15", make_function(&GetRegister<XMM15>, reference_existing_object_policy()))
#endif

		// The following registers are currently not supported by DynamicHooks
		/*
		.add_property("st1", make_function(&GetRegister<ST1>, reference_existing_object_policy()))
		.add_property("st2", make_function(&GetRegister<ST2>, reference_existing_object_policy()))
		.add_property("st3", make_function(&GetRegister<ST3>, reference_existing_object_policy()))
		.add_property("st4", make_function(&GetRegister<ST4>, reference_existing_object_policy()))
		.add_property("st5", make_function(&GetRegister<ST5>, reference_existing_object_policy()))
		.add_property("st6", make_function(&GetRegister<ST6>, reference_existing_object_policy()))
		.add_property("st7", make_function(&GetRegister<ST7>, reference_existing_object_policy()))
		*/
	;
}


// ============================================================================
// >> ICallingConventionWrapper
// ============================================================================
void export_calling_convention(scope _memory)
{
	class_<ICallingConventionWrapper, boost::shared_ptr<ICallingConventionWrapper>, boost::noncopyable>(
		"CallingConvention",
		"An an abstract class that is used to create custom calling "
		"conventions (only available for hooking function and not for"
		" calling functions).\n",
		no_init)

		.def("__init__",
			make_constructor(
				&ICallingConventionWrapper::__init__,
				post_constructor_policies<
					initialize_wrapper_policies<boost::shared_ptr<ICallingConventionWrapper> >
				>(
					make_function(
						&ICallingConventionWrapper::Initialize,
						default_call_policies(),
						args("self", "arg_types", "return_type", "alignment", "default_convention")
					)
				),
				("arg_types", "return_type", arg("alignment")=(int) sizeof(void*), arg("default_convention")=CONV_CUSTOM)
			),
			"Initialize the calling convention.\n"
			"\n"
			":param iterable arg_types: A list of :class:`DataType` values that define the argument types of a function.\n"
			":param DataType return_type: The return type of a function.\n"
			":param int alignment: The stack alignment.\n"
			":param Convention_t default_convention: The default convention for un override function."
		)

		.def("get_registers",
			&ICallingConventionWrapper::GetRegistersList,
			"Return a list of :class:`Register` values. These registeres will be saved for later access."
		)

		.def("get_pop_size",
			&ICallingConventionWrapper::GetPopSize,
			"Return the number of bytes that should be added to the stack to clean up."
		)

		.def("get_argument_ptr",
			&ICallingConventionWrapper::GetArgumentPtr,
			(arg("index"), arg("registers")),
			"Return a pointer to the argument at the given index.\n"
			"\n"
			":param int index: The index of the argument.\n"
			":param Registers registers: A snapshot of all saved registers.",
			return_by_value_policy()
		)

		.def("argument_ptr_changed",
			&ICallingConventionWrapper::ArgumentPtrChanged,
			(arg("index"), arg("registers"), arg("ptr")),
			"Called when the argument pointer returned by :meth:`get_argument_ptr` has been changed.\n"
			"\n"
			":param int index: The index of the argument that has been changed.\n"
			":param Registers registers: A snapshot of all saved registers.\n"
			":param Pointer ptr: The argument pointer that has been changed."
		)

		.def("get_return_ptr",
			&ICallingConventionWrapper::GetReturnPtr,
			(arg("registers")),
			"Return a pointer to the return value.\n"
			"\n"
			":param Registers registers: A snapshot of all saved registers.",
			return_by_value_policy()
		)

		.def("return_ptr_changed",
			&ICallingConventionWrapper::ReturnPtrChanged,
			(arg("registers"), arg("ptr")),
			"Called when the return value pointer returned by :meth:`get_return_ptr` has been changed.\n"
			"\n"
			":param Registers registers: A snapshot of all saved registers.\n"
			":param Pointer ptr: The return value pointer that has been changed."
		)

		.add_property("argument_types",
			&ICallingConventionWrapper::GetArgTypes,
			"A list of :class:`DataType` values that define the argument types of a function."
		)

		.def_readonly("return_type",
			&ICallingConventionWrapper::m_returnType,
			"A :class:`DataType` value that defines the return type of a function."
		)

		.def_readonly("alignment",
			&ICallingConventionWrapper::m_iAlignment,
			"An integer that defines the stack alignment."
		)

		ADD_MEM_TOOLS_WRAPPER(ICallingConventionWrapper, ICallingConvention)
	;
}


// ============================================================================
// >> FUNCTIONS
// ============================================================================
void export_functions(scope _memory)
{
	def("find_binary",
		&FindBinary,
		("path", arg("srv_check")=true, arg("check_extension")=true),
		"Search for a binary and return it as a :class:`BinaryFile` object.\n"
		"\n"
		":param str path: The path to the binary file (absolute, relative or just the name of the file if it's on the search path).\n"
		":param bool srv_check: If True it will automatically check the binary for the '_srv' ending on Linux.",
		reference_existing_object_policy()
	);
	
	def("alloc",
		Alloc,
		("size", arg("auto_dealloc")=true),
		"Allocate a memory block.\n"
		"\n"
		":param int size: The size (in bytes) of the memory block.\n"
		":param bool auto_dealloc: If True the memory block will be deallocated automatically when the return value goes out of the scope.",
		manage_new_object_policy()
	);

	def("get_object_pointer",
		&GetObjectPointer,
		(arg("obj")),
		"Return the pointer of the C++ object of a given Python object.\n"
		"\n"
		":param obj: The object you want to retrieve a pointer from."
	);

	def("make_object",
		GET_FUNCTION(object, MakeObject, object, object),
		(arg("cls"), arg("ptr")),
		"Wrap a pointer using an exposed class.\n"
		"\n"
		":param cls: The class that should be used to wrap the pointer.\n"
		":param Pointer ptr: The pointer that should be wrapped."
	);

	def("make_object",
		GET_FUNCTION(object, MakeObject, object, CPointer *),
		(arg("cls"), arg("ptr")),
		"Wrap a pointer using an exposed class.\n"
		"\n"
		":param cls: The class that should be used to wrap the pointer.\n"
		":param Pointer ptr: The pointer that should be wrapped."
	);

	def("get_size",
		&GetSize,
		(arg("cls")),
		"Return the size of a class or class object of its C++ class.\n"
		"\n"
		":param cls: A class or class object."
	);

	def("get_data_type_size",
		&GetDataTypeSize,
		("data_type", arg("alignment")=(int) sizeof(void*)),
		"Return the size of the data type after applying alignment.\n"
		"\n"
		":param DataType data_type: The data type you would like to get the size of.\n"
		":param int alignment: The alignment that should be used."
	);

	def("get_hooks_disabled",
		&GetHooksDisabled,
		"Return whether or not hook callbacks are disabled.\n"
		"\n"
		":rtype: bool");

	def("set_hooks_disabled",
		&SetHooksDisabled,
		"Set whether or not hook callbacks are disabled.\n"
		"\n"
		":param bool disabled: If ``True``, hook callbacks are disabled.");
}


// ============================================================================
// >> GLOBAL VARIABLES
// ============================================================================
DeferredDict g_oExposedClasses;
DeferredDict g_oClassInfo;

#define ADD_NATIVE_TYPE_SIZE(name, type) \
	scope().attr("TYPE_SIZES")[name] = sizeof(type);

void export_global_variables(scope _memory)
{
	_memory.attr("EXPOSED_CLASSES") = g_oExposedClasses.get();
	_memory.attr("CLASS_INFO") = g_oClassInfo.get();

	// Don't remove this! It's required for the ADD_NATIVE_TYPE_SIZE macro.
	_memory.attr("TYPE_SIZES") = dict();

	// Native types
	ADD_NATIVE_TYPE_SIZE("BOOL", bool)
	ADD_NATIVE_TYPE_SIZE("CHAR", char)
	ADD_NATIVE_TYPE_SIZE("UCHAR", unsigned char)
	ADD_NATIVE_TYPE_SIZE("SHORT", short)
	ADD_NATIVE_TYPE_SIZE("USHORT", unsigned short)
	ADD_NATIVE_TYPE_SIZE("INT", int)
	ADD_NATIVE_TYPE_SIZE("UINT", unsigned int)
	ADD_NATIVE_TYPE_SIZE("LONG", long)
	ADD_NATIVE_TYPE_SIZE("ULONG", unsigned long)
	ADD_NATIVE_TYPE_SIZE("LONG_LONG", long long)
	ADD_NATIVE_TYPE_SIZE("ULONG_LONG", unsigned long long)
	ADD_NATIVE_TYPE_SIZE("FLOAT", float)
	ADD_NATIVE_TYPE_SIZE("DOUBLE", double)
	ADD_NATIVE_TYPE_SIZE("POINTER", void*)
	ADD_NATIVE_TYPE_SIZE("STRING", char*)

	_memory.attr("NULL") = object(CPointer());

}


// ============================================================================
// >> Protection_t
// ============================================================================
void export_protection(scope _memory)
{
	enum_<Protection_t> Protection("Protection");
	
	Protection.value("NONE", PROTECTION_NONE);
	Protection.value("READ", PROTECTION_READ);
	Protection.value("READ_WRITE", PROTECTION_READ_WRITE);
	Protection.value("EXECUTE", PROTECTION_EXECUTE);
	Protection.value("EXECUTE_READ", PROTECTION_EXECUTE_READ);
	Protection.value("EXECUTE_READ_WRITE", PROTECTION_EXECUTE_READ_WRITE);
}
