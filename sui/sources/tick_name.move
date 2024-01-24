module smartinscription::tick_name{
    use std::ascii;
    use std::vector;
    use std::option;
    use smartinscription::string_util;
    
    const DISALLOWED_TICK_CHARS: vector<u8> = b" .\"'\\/<>?;:[]{}()!@#$%^&*+=|~-,`";
    const MAX_TICK_LENGTH: u64 = 32;
    const MIN_TICK_LENGTH: u64 = 4;

    const RESERVED_TICK_TICK: vector<u8> = b"TICK";
    const RESERVED_TICK_NAME: vector<u8> = b"NAME";

    public fun is_tick_name_reserved(tick_name: vector<u8>) : bool {
        string_util::to_uppercase(&mut tick_name);
        tick_name == RESERVED_TICK_TICK || tick_name == RESERVED_TICK_NAME
    }

    /// Check if the tick name is valid
    public fun is_tick_name_valid(tick_name: vector<u8>) : bool {
        let tick_len = vector::length(&tick_name);
        if(tick_len < MIN_TICK_LENGTH || tick_len > MAX_TICK_LENGTH) {
            return false
        };
        if (string_util::contains_any(&tick_name, &DISALLOWED_TICK_CHARS)){
            return false
        };
        let str_opt = ascii::try_string(tick_name);
        if(option::is_none(&str_opt)) {
            return false
        };
        let tick_name = option::destroy_some(str_opt);
        ascii::all_characters_printable(&tick_name)
    }

    #[test]
    fun test_is_tick_name_valid() {
        assert!(!is_tick_name_valid(b"abc"), 1);
        assert!(!is_tick_name_valid(b"123456789012345678901234567890123"), 1);
        assert!(is_tick_name_valid(b"abcd"), 2);
        assert!(is_tick_name_valid(b"ab_d"), 2);
        assert!(!is_tick_name_valid(b"abc!"), 3);
        assert!(!is_tick_name_valid(b"abc "), 4);
        assert!(!is_tick_name_valid(b"abc."), 5);
        assert!(!is_tick_name_valid(b"abc@"), 6);
        assert!(!is_tick_name_valid(b"abc#"), 7);
        assert!(!is_tick_name_valid(b"abc$"), 8);
        assert!(!is_tick_name_valid(b"abc&"), 9);
        assert!(!is_tick_name_valid(b"abc="), 10);
        assert!(!is_tick_name_valid(b"abc+"), 11);
        assert!(!is_tick_name_valid(b"abc-"), 12);
        assert!(!is_tick_name_valid(b"abc*"), 13);
        assert!(!is_tick_name_valid(b"abc/"), 14);
        assert!(!is_tick_name_valid(b"abc\\"), 15);
        assert!(!is_tick_name_valid(b"abc|"), 16);
        assert!(!is_tick_name_valid(b"abc<"), 17);
        assert!(!is_tick_name_valid(b"abc>"), 18);
        assert!(!is_tick_name_valid(b"abc,"), 19);
        assert!(!is_tick_name_valid(b"abc?"), 20);
        assert!(!is_tick_name_valid(b"abc;"), 21);
        assert!(!is_tick_name_valid(b"abc:"), 22);
        assert!(!is_tick_name_valid(b"abc["), 23);
        assert!(!is_tick_name_valid(b"abc]"), 24);
        assert!(!is_tick_name_valid(b"abc{"), 25);
        assert!(!is_tick_name_valid(b"abc}"), 26);
        assert!(!is_tick_name_valid(b"abc("), 27);
        assert!(!is_tick_name_valid(b"abc)"), 28);
        assert!(!is_tick_name_valid(b"abc'"), 29);
        assert!(!is_tick_name_valid(b"abc\""), 30);
        assert!(!is_tick_name_valid(b"abc`"), 31);
        assert!(!is_tick_name_valid(b"abc~"), 32);
    }
}