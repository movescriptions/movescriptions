/// This module contains the metadata struct, which is used to store metadata in the BCS.
module smartinscription::metadata {
    use std::option;
    use sui::bcs;
    use smartinscription::movescription::{Self, Metadata};
    use smartinscription::content_type;
    use smartinscription::type_util;

    const ErrorInvalidMetadata: u64 = 1;
    const ErrorInvalidMetadataType: u64 = 2;
    
    /// BCS text metadata, which is a string with a timestamp and miner address
    /// We use vector<u8> instead of String because we want to be able to support `ascii::String` and `string::String`.
    struct TextMetadata has store, copy, drop{
        text: vector<u8>,
        timestamp_ms: u64,
        miner: address,
    }

    public fun new_ascii_metadata(text: std::ascii::String, timestamp_ms: u64, miner: address): TextMetadata {
        TextMetadata{
            text: std::ascii::into_bytes(text),
            timestamp_ms,
            miner,
        }
    }

    public fun new_string_metadata(text: std::string::String, timestamp_ms: u64, miner: address): TextMetadata{
        TextMetadata{
            text: *std::string::bytes(&text),
            timestamp_ms,
            miner,
        }
    }

    public fun decode_text_metadata(metadata: &Metadata) : TextMetadata {
        let ct = movescription::metadata_content_type(metadata);
        let content = movescription::metadata_content(metadata);
        assert!(content_type::is_bcs(&ct), ErrorInvalidMetadata);
        let type_name = content_type::get_bcs_type_name(&ct);
        let type_name = option::destroy_with_default(type_name, std::ascii::string(b""));
        assert!(type_name == type_util::type_to_name<TextMetadata>(), ErrorInvalidMetadataType);
        let bcs = bcs::new(content);
        let text = bcs::peel_vec_u8(&mut bcs);
        let timestamp_ms = bcs::peel_u64(&mut bcs);
        let miner = bcs::peel_address(&mut bcs);
        TextMetadata{
            text,
            timestamp_ms,
            miner
        }
    }

    public fun unpack_text_metadata(text_metadata: TextMetadata): (vector<u8>, u64, address){
        let TextMetadata{text, timestamp_ms, miner} = text_metadata;
        (text, timestamp_ms, miner)
    }

    public fun text_metadata_text(text_metadata: &TextMetadata) : &vector<u8>{
        &text_metadata.text
    }

    public fun text_metadata_timestamp(text_metadata: &TextMetadata): u64{
        text_metadata.timestamp_ms
    }

    public fun text_metadata_miner(text_metadata: &TextMetadata) : address{
        text_metadata.miner
    }
    

    #[test]
    fun test_text_metadata(){
        let text = std::ascii::string(b"test");
        let timestamp_ms = 10000;
        let miner = @0xABCD;

        let text_metata = new_ascii_metadata(text , timestamp_ms, miner);
        let metadata = content_type::new_bcs_metadata(&text_metata);
        let decoded_text_metadata = decode_text_metadata(&metadata);
        assert!(std::ascii::string(decoded_text_metadata.text) == text, 1);
        assert!(decoded_text_metadata.timestamp_ms == timestamp_ms, 2);
        assert!(decoded_text_metadata.miner == miner, 3); 
    }
}