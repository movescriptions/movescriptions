use clap::{Parser, Subcommand};
use movescription::hash::pow;

#[derive(Parser)]
#[command(name = "movescription")]
#[command(bin_name = "movescription")]
struct MovescriptionCli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    Pow {
        /// hex input data
        #[arg(short = 'i', long)]
        input: String,

        #[arg(short = 'd', long)]
        difficulty: u64,
    },
}

fn main() {
    let _ = tracing_subscriber::fmt::try_init();
    let cli = MovescriptionCli::parse();
    match cli.command {
        Commands::Pow {
            input: data,
            difficulty,
        } => {
            let data = hex::decode(data.strip_prefix("0x").unwrap_or(data.as_str())).unwrap();
            let start_time = std::time::Instant::now();
            let (hash, nonce) = pow(&data, difficulty);
            println!(
                "difficulty: {}, hash: {}, nonce: {}, use millis: {}",
                difficulty,
                hex::encode(hash),
                nonce,
                start_time.elapsed().as_millis()
            );
        }
    }
}
