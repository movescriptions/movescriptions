
export interface Metadata {
  content_type: string 
  content: Uint8Array,
}

export interface Movescription {
  object_id: string;
  tick: string;
  value: number;
  metadata?: Metadata;
}
