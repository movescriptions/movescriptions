#[allow(implicit_const_copy)]
module smartinscription::type_util{
    use std::type_name;
    use std::vector;
    use std::ascii::{Self, String};
    use smartinscription::string_util;

    const ErrorInvalidStruct : u64 = 1;
    const ErrorInvalidWitness : u64 = 2;

    const WITNESS_STRUCT_NAME : vector<u8> = b"WITNESS";
    const SPLIT : vector<u8> = b"::";
    
    public fun type_to_name<T>() : String {
        type_name::into_string(type_name::get_with_original_ids<T>())
    }

    public fun is_witness<T>() : bool {
        let struct_name = struct_name<T>();
        ascii::into_bytes(struct_name) == WITNESS_STRUCT_NAME
    }

    public fun assert_witness<T>(expect_module: String) {
        assert!(check_witness<T>(expect_module), ErrorInvalidWitness);
    }

    /// Checks if the witness of a type is the expected module.
    public fun check_witness<T>(expect_module: String) : bool {
        let type_name = ascii::into_bytes(type_to_name<T>());
        let expect_name = ascii::into_bytes(expect_module);
        vector::append(&mut expect_name, SPLIT);
        vector::append(&mut expect_name, WITNESS_STRUCT_NAME);
        type_name == expect_name
    }

    /// Returns the module address and name of a type.
    public fun module_id<T>() : String {
        let type_name = ascii::into_bytes(type_to_name<T>());
        let (found, index) = string_util::last_index_of(&type_name, &SPLIT);
        assert!(found, ErrorInvalidStruct);
        ascii::string(string_util::substring(&type_name, 0, index))
    }

    /// Returns the struct name of a type.
    public fun struct_name<T>() : String {
        let type_name = ascii::into_bytes(type_to_name<T>());
        let (found, index) = string_util::last_index_of(&type_name, &SPLIT);
        assert!(found, ErrorInvalidStruct);
        ascii::string(string_util::substring(&type_name, index + 2, vector::length(&type_name)))
    }

    #[test_only]
    struct WITNESS has drop{}

    #[test]
    fun test_module_id() {
        let module_id = module_id<WITNESS>();
        //std::debug::print(&module_id);
        let expect_module_id = b"0000000000000000000000000000000000000000000000000000000000000000";
        vector::append(&mut expect_module_id, SPLIT);
        vector::append(&mut expect_module_id, b"type_util");
        let expect_module_id = ascii::string(expect_module_id);
        //std::debug::print(&expect_module_id);
        assert!(module_id == expect_module_id, 1);
    }

    #[test]
    fun test_struct_name() {
        let struct_name = struct_name<WITNESS>();
        let expect_struct_name = ascii::string(WITNESS_STRUCT_NAME);
        assert!(struct_name == expect_struct_name, 1);
    }

    #[test]
    #[expected_failure]
    fun test_struct_name_failed(){
        struct_name<u64>();
    }

    #[test]
    #[expected_failure]
    fun test_module_id_failed(){
        module_id<u64>();
    }
}