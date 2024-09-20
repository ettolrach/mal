use std::io::Write;

use rust::types::Mal;
use rust::reader;
use rust::printer;

fn main() -> std::io::Result<()> {
    loop {
        write!(std::io::stdout(), "user> ")?;
        std::io::stdout().flush()?;
        let mut line = String::new();
        let bytes = std::io::stdin().read_line(&mut line)?;
        let input = line.trim();

        // Handle EOF/Ctrl+D.
        if bytes == 0 {
            break;
        }

        writeln!(std::io::stdout(), "{}", rep(input))?;
    }
    println!();
    Ok(())
}

fn read(s: &str) -> Mal {
    reader::read_str(s)
}

fn eval(s: &Mal) -> Mal {
    s.clone()
}

fn print(mal: &Mal) -> String {
    printer::pr_str(mal)
}

fn rep(s: &str) -> String {
    print(&eval(&read(s)))
}
