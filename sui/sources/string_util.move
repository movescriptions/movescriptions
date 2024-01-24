module smartinscription::string_util {
    use std::vector;

    public fun to_uppercase(input:&mut vector<u8>) {
        let length = vector::length(input);
        let i = 0;
        while (i < length) {
            let letter = vector::borrow_mut(input, i);
            if (is_lowercase(*letter)) {
                *letter = *letter - 32;
            };
            i = i + 1;
        }
    }

    public fun to_lowercase(input:&mut vector<u8>) {
        let length = vector::length(input);
        let i = 0;
        while (i < length) {
            let letter = vector::borrow_mut(input, i);
             if (is_uppercase(*letter)) {
                  *letter = *letter + 32;
            };
            i = i + 1;
        }
    }

    public fun is_lowercase(letter: u8): bool {
        letter >= 97 && letter <= 122
    }

    public fun is_uppercase(letter: u8): bool {
        letter >= 65 && letter <= 90
    }

    public fun starts_with(input:&vector<u8>, prefix:&vector<u8>): bool {
        let input_length = vector::length(input);
        let prefix_length = vector::length(prefix);
        if (input_length < prefix_length) {
            return false
        };
        let i = 0;
        while (i < prefix_length) {
            if (vector::borrow(input, i) != vector::borrow(prefix, i)) {
                return false
            };
            i = i + 1;
        };
        true
    }

    /// Returns if the input contains the search string and the index of the first match
    public fun index_of(input:&vector<u8>, search:&vector<u8>): (bool, u64) {
        let input_length = vector::length(input);
        let search_length = vector::length(search);
        if (input_length < search_length) {
            return (false, 0)
        };
        let i = 0;
        while (i < input_length) {
            let j = 0;
            while (j < search_length) {
                let idx = i + j;
                if ( idx >= input_length) {
                    break
                };
                if (vector::borrow(input, idx) != vector::borrow(search, j)) {
                    break
                };
                j = j + 1;
            };
            if (j == search_length) {
                return (true, i)
            };
            i = i + 1;
        };
        (false, 0)
    }

    /// Returns if the input contains the search string and the index of the last match
    public fun last_index_of(input:&vector<u8>, search:&vector<u8>): (bool, u64) {
        let input_length = vector::length(input);
        let search_length = vector::length(search);
        if (input_length < search_length) {
            return (false, 0)
        };
        let i = input_length - search_length;
        while (i >= 0) {
            let j = 0;
            while (j < search_length) {
                let idx = i + j;
                if ( idx >= input_length) {
                    break
                };
                if (vector::borrow(input, idx) != vector::borrow(search, j)) {
                    break
                };
                j = j + 1;
            };
            if (j == search_length) {
                return (true, i)
            };
            if (i == 0){
                break
            };
            i = i - 1;
        };
        (false, 0)
    }

    public fun substring(input:&vector<u8>, start:u64, end:u64): vector<u8> {
        let length = vector::length(input);
        if (start >= length) {
            return vector::empty()
        };
        let end = if (end > length) {
            length
        } else {
            end
        };
        let result = vector::empty();
        let i = start;
        while (i < end) {
            vector::push_back(&mut result, *vector::borrow(input, i));
            i = i + 1;
        };
        result
    }

    /// Returns if the input contains any of the chars
    public fun contains_any(input: &vector<u8>, chars: &vector<u8>): bool {
        let length = vector::length(input);
        let chars_length = vector::length(chars);
        let i = 0;
        while (i < length) {
            let j = 0;
            while (j < chars_length) {
                if (vector::borrow(input, i) == vector::borrow(chars, j)) {
                    return true
                };
                j = j + 1;
            };
            i = i + 1;
        };
        false
    }

    #[test]
    fun test_index_of() {
        let input = b"abcabc";
        let search = b"abc";
        let (found, index) = index_of(&input, &search);
        assert!(found, 1);
        assert!(index == 0, 2);

        let input = b"abcabc";
        let search = b"bc";
        let (found, index) = index_of(&input, &search);
        assert!(found, 3);
        assert!(index == 1, 4);

        let input = b"abcabc";
        let search = b"cd";
        let (found, index) = index_of(&input, &search);
        assert!(!found, 5);
        assert!(index == 0, 6);

        let input = b"abcabc";
        let search = b"abcabc";
        let (found, index) = index_of(&input, &search);
        assert!(found, 7);
        assert!(index == 0, 8);

        let input = b"abcabc";
        let search = b"abcabcx";
        let (found, index) = index_of(&input, &search);
        assert!(!found, 9);
        assert!(index == 0, 10);
    }

    #[test]
    fun test_last_index_of(){
        let input = b"abcabc";
        let search = b"abc";
        let (found, index) = last_index_of(&input, &search);
        assert!(found, 1);
        assert!(index == 3, 2);

        let input = b"abcabc";
        let search = b"bc";
        let (found, index) = last_index_of(&input, &search);
        assert!(found, 3);
        assert!(index == 4, 4);

        let input = b"abcabc";
        let search = b"cd";
        let (found, index) = last_index_of(&input, &search);
        assert!(!found, 5);
        assert!(index == 0, 6);

        let input = b"abcabc";
        let search = b"abcabc";
        let (found, index) = last_index_of(&input, &search);
        assert!(found, 7);
        assert!(index == 0, 8);

        let input = b"abcabc";
        let search = b"abcabcx";
        let (found, index) = last_index_of(&input, &search);
        assert!(!found, 9);
        assert!(index == 0, 10);
    }

    #[test]
    fun test_substring(){
        let input = b"abcabc";
        let result = substring(&input, 0, 3);
        assert!(result == b"abc", 1);

        let input = b"abcabc";
        let result = substring(&input, 0, 6);
        assert!(result == b"abcabc", 2);

        let input = b"abcabc";
        let result = substring(&input, 0, 7);
        assert!(result == b"abcabc", 3);

        let input = b"abcabc";
        let result = substring(&input, 0, 0);
        assert!(result == b"", 4);

        let input = b"abcabc";
        let result = substring(&input, 0, 1);
        assert!(result == b"a", 5);

        let input = b"abcabc";
        let result = substring(&input, 1, 3);
        assert!(result == b"bc", 6);
    }

    #[test]
    fun test_contains_any(){
        let input = b"abcabc";
        let chars = b"ac";
        assert!(contains_any(&input, &chars), 1);

        let input = b"abcabc";
        let chars = b"da";
        assert!(contains_any(&input, &chars), 2);

        let input = b"abcabc";
        let chars = b"de";
        assert!(!contains_any(&input, &chars), 3);
    }

    #[test]
    #[expected_failure(location = Self, abort_code = 1)]
    fun test_is_lowercase() {
        let vec = b"aA";
        assert!(is_lowercase(*vector::borrow(&vec,0)),1);
        assert!(is_lowercase(*vector::borrow(&vec,1)),1);
    }

    #[test]
    #[expected_failure(location = Self, abort_code = 2)]
    fun test_is_uppercase() {
        let vec = b"aA";
        assert!(is_uppercase(*vector::borrow(&vec,1)),2);
        assert!(is_uppercase(*vector::borrow(&vec,0)),2);
    }
    

    #[test]
    fun test_to_uppercase() {
        let vec = b"aA-Xz";
        to_uppercase(&mut vec);
        assert!(vec == b"AA-XZ",1);
    }

    #[test]
    fun test_to_lowercase() {
        let vec = b"aA-Xz";
        to_lowercase(&mut vec);
        assert!(vec == b"aa-xz",1);
    }
}