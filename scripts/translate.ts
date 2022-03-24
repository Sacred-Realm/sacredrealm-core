import fs from 'fs';

async function translate() {
    const files = fs.readdirSync(`text`);
    for (let file of files) {
        const json = JSON.parse(fs.readFileSync(`text/${file}`).toString());
        const text = json.reduce((pre: any, cur: any) => pre + cur.Text_Korean + '\n', 0);
        // fs.writeFileSync(`temp/${file}`, text);
        const temp = fs.readFileSync(`temp/${file}`).toString().split('\n');
        for (let i = 0; i < json.length; i++) {
            json[i].Text_Korean = temp[i];
        }
        fs.writeFileSync(`output/${file}`, JSON.stringify(json));
    }
}

translate();
