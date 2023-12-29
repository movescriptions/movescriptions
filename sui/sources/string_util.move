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