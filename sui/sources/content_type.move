module smartinscription::content_type{
    use std::string::{Self, String};
    use sui::bcs;
    use smartinscription::movescription::{Self, Metadata};
    use smartinscription::string_util;
    use smartinscription::type_util;

    const CONTENT_TYPE_TEXT_PLAIN: vector<u8>  = b"text/plain";
    const CONTENT_TYPE_TEXT_HTML: vector<u8>  = b"text/html";
    const CONTENT_TYPE_TEXT_CSS: vector<u8>  = b"text/css";
    const CONTENT_TYPE_TEXT_JAVASCRIPT: vector<u8>  = b"text/javascript";
    const CONTENT_TYPE_TEXT_XML: vector<u8>  = b"text/xml";

    const CONTENT_TYPE_IMAGE_JPEG: vector<u8>  = b"image/jpeg";
    const CONTENT_TYPE_IMAGE_PNG: vector<u8>  = b"image/png";
    const CONTENT_TYPE_IMAGE_GIF: vector<u8>  = b"image/gif";
    const CONTENT_TYPE_IMAGE_SVG: vector<u8>  = b"image/svg+xml";
    const CONTENT_TYPE_IMAGE_BMP: vector<u8>  = b"image/bmp";
    const CONTENT_TYPE_IMAGE_WEBP: vector<u8>  = b"image/webp";

    const CONTENT_TYPE_APPLICATION_JSON: vector<u8>  = b"application/json";
    const CONTENT_TYPE_APPLICATION_PDF: vector<u8>  = b"application/pdf";
    const CONTENT_TYPE_APPLICATION_BCS: vector<u8>  = b"application/bcs";

    public fun content_type_text_plain(): String{
        string::utf8(CONTENT_TYPE_TEXT_PLAIN)
    }

    public fun content_type_text_html(): String{
        string::utf8(CONTENT_TYPE_TEXT_HTML)
    }

    public fun content_type_text_css(): String{
        string::utf8(CONTENT_TYPE_TEXT_CSS)
    }

    public fun content_type_text_javascript(): String{
        string::utf8(CONTENT_TYPE_TEXT_JAVASCRIPT)
    }

    public fun content_type_text_xml(): String{
        string::utf8(CONTENT_TYPE_TEXT_XML)
    }

    public fun content_type_image_jpeg(): String{
        string::utf8(CONTENT_TYPE_IMAGE_JPEG)
    }

    public fun content_type_image_png(): String{
        string::utf8(CONTENT_TYPE_IMAGE_PNG)
    }

    public fun content_type_image_gif(): String{
        string::utf8(CONTENT_TYPE_IMAGE_GIF)
    }

    public fun content_type_image_svg(): String{
        string::utf8(CONTENT_TYPE_IMAGE_SVG)
    }

    public fun content_type_image_bmp(): String{
        string::utf8(CONTENT_TYPE_IMAGE_BMP)
    }

    public fun content_type_image_webp(): String{
        string::utf8(CONTENT_TYPE_IMAGE_WEBP)
    }

    public fun content_type_application_json(): String{
        string::utf8(CONTENT_TYPE_APPLICATION_JSON)
    }

    public fun content_type_application_pdf(): String{
        string::utf8(CONTENT_TYPE_APPLICATION_PDF)
    }

    public fun content_type_application_bcs(): String{
        string::utf8(CONTENT_TYPE_APPLICATION_BCS)
    }

    public fun content_type_application_bcs_with_type_name(type_name: String): String{
        let content_type = string::utf8(CONTENT_TYPE_APPLICATION_BCS);
        string::append_utf8(&mut content_type, b"; type_name=");
        string::append(&mut content_type, type_name);
        content_type
    }
    
    public fun is_text(content_type: &String): bool{
        string_util::starts_with(string::bytes(content_type), &b"text/") || string::bytes(content_type) == &CONTENT_TYPE_APPLICATION_JSON
    }

    public fun is_image(content_type: &String): bool{
        string_util::starts_with(string::bytes(content_type), &b"image/")
    }

    public fun is_bcs(content_type: &String): bool{
        string_util::starts_with(string::bytes(content_type), &CONTENT_TYPE_APPLICATION_BCS)
    }

    public fun new_string_metadata(text: &String): Metadata{
        movescription::new_metadata(content_type_text_plain(), *string::bytes(text))
    }

    public fun new_ascii_metadata(text: &std::ascii::String): Metadata {
        movescription::new_metadata(content_type_text_plain(), *std::ascii::as_bytes(text))
    }

    public fun new_bcs_metadata<T>(content: &T): Metadata {
        let bytes = bcs::to_bytes(content);
        let type_name = string::from_ascii(type_util::type_to_name<T>());
        movescription::new_metadata(content_type_application_bcs_with_type_name(type_name), bytes)
    }

    #[test]
    fun test_is_text(){
        assert!(is_text(&string::utf8(b"text/plain")), 1);
        assert!(is_text(&string::utf8(b"application/json")), 6);
        assert!(!is_text(&string::utf8(b"image/jpeg")), 7);

    }

    #[test]
    fun test_is_image(){
        assert!(is_image(&string::utf8(b"image/jpeg")), 2);
        assert!(!is_image(&string::utf8(b"text/plain")), 3); 
    }
}