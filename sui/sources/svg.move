module smartinscription::svg {
    use std::vector;
    
    const SVG_PATH_1:vector<u8> = b"data:image/svg+xml,%3Csvg%20width%3D%22120%22%20height%3D%22120%22%20viewBox%3D%220%200%20120%20120%22%20fill%3D%22none%22%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%3E%3Crect%20width%3D%22120%22%20height%3D%22120%22%20fill%3D%22%234CA2FF%22%2F%3E%3Ctext%20fill%3D%22%23EAF7FF%22%20xml%3Aspace%3D%22preserve%22%20style%3D%22white-space%3A%20pre%22%20font-family%3D%22Inter%22%20font-size%3D%2212%22%20letter-spacing%3D%220em%22%3E%3Ctspan%20x%3D%2215%22%20y%3D%2226.8636%22%3E%7B%26%2310%3B%3C%2Ftspan%3E%3Ctspan%20x%3D%2215%22%20y%3D%2241.8636%22%3E%20%20%20%20p%3A%20%26%2339%3B";
    const SVG_PATH_2:vector<u8> = b"%26%2339%3B%2C%26%2310%3B%3C%2Ftspan%3E%3Ctspan%20x%3D%2215%22%20y%3D%2256.8636%22%3E%20%20%20%20op%3A%20%26%2339%3B";
    const SVG_PATH_3:vector<u8> = b"%26%2339%3B%2C%26%2310%3B%3C%2Ftspan%3E%3Ctspan%20x%3D%2215%22%20y%3D%2271.8636%22%3E%20%20%20%20tick%3A%20%26%2339%3B";
    const SVG_PATH_4:vector<u8> = b"%26%2339%3B%2C%26%2310%3B%3C%2Ftspan%3E%3Ctspan%20x%3D%2215%22%20y%3D%2286.8636%22%3E%20%20%20%20amt%3A%20";
    const SVG_PATH_5:vector<u8> = b"%26%2310%3B%3C%2Ftspan%3E%3Ctspan%20x%3D%2215%22%20y%3D%22101.864%22%3E%7D%3C%2Ftspan%3E%3C%2Ftext%3E%3C%2Fsvg%3E";

    public fun generateSVG(p:vector<u8>,op:vector<u8>,tick:vector<u8>,amt:vector<u8>):vector<u8>{
      let metadata = SVG_PATH_1;
      vector::append(&mut metadata, p);
      vector::append(&mut metadata, SVG_PATH_2);
      vector::append(&mut metadata, op);
      vector::append(&mut metadata, SVG_PATH_3);
      vector::append(&mut metadata, tick);
      vector::append(&mut metadata, SVG_PATH_4);
      vector::append(&mut metadata, amt);
      vector::append(&mut metadata, SVG_PATH_5);

      metadata
    }

}