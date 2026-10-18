fn main() {
    #[cfg(windows)]
    embed_resource::compile("rescale.rc", embed_resource::NONE);
}
