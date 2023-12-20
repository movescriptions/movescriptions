module movescriptions::util{
    use std::vector;
    use std::string::String;
    
    public fun to_lower_case(s: String) : String {
        //TODO
        s
    }

    public fun split_vector<T: copy>(v: &vector<T>, part_len: u64) : vector<vector<T>>{
        let result = vector[];
        let length = vector::length(v);
        let i = 0u64;
        while(i < length){
            let part = vector<T>[];
            let j = 0;
            while(j < part_len && i < length){
                vector::push_back(&mut part, *vector::borrow(v, i));
                i = i + 1;
                j = j + 1;
            };
            vector::push_back(&mut result, part);
        };
        result
    } 

    #[test]
    fun test_split(){
        let v = vector[1,2,3,4,5,6,7,8,9,10];
        let result = split_vector(&v, 3u64);
        //std::debug::print(&result);
        assert!(vector::length(&result) == 4u64, 1);
        assert!(vector::length(vector::borrow(&result, 0)) == 3u64, 2);
        assert!(vector::length(vector::borrow(&result, 1)) == 3u64, 3);
        assert!(vector::length(vector::borrow(&result, 2)) == 3u64, 4);
        assert!(vector::length(vector::borrow(&result, 3)) == 1u64, 5);
    }
}
