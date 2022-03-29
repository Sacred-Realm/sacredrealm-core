import fs from 'fs';

async function translate() {
    const files = fs.readdirSync(`output`);
    // for (let file of files) {
    //     const json = JSON.parse(fs.readFileSync(`text/${file}`).toString());
    //     const text = json.reduce((pre: any, cur: any) => pre + cur.Text_Korean + '\n', 0);
    //     // fs.writeFileSync(`temp/${file}`, text);
    //     const temp = fs.readFileSync(`temp/${file}`).toString().split('\n');
    //     for (let i = 0; i < json.length; i++) {
    //         json[i].Text_Korean = temp[i];
    //     }
    //     fs.writeFileSync(`output/${file}`, JSON.stringify(json));
    // }
    for (let file of files) {
        const json = JSON.parse(fs.readFileSync(`output/${file}`).toString());
        const text = json.reduce((pre: any, cur: any) => pre + (cur.Text_English ? '' : cur.Text_Korean) + '\n', 0);
        // fs.writeFileSync(`temp2/${file}`, text);
        const temp = fs.readFileSync(`temp2/${file}`).toString().split('\n');
        for (let i = 0; i < json.length; i++) {
            if (temp[i]) json[i].Text_English = temp[i];
        }
        fs.writeFileSync(`output2/${file}`, JSON.stringify(json));
    }
}

translate();
