const { IPC } = BareKit;
const Hyperswarm = require('hyperswarm');
const Hyperdrive = require('hyperdrive');
const b4a = require('b4a');
const Corestore = require('corestore');

const store = new Corestore("/tmp/landmark");
const swarm = new Hyperswarm();


let drive;

IPC.on("data", async (chunk) => {
    let req;
    try {
        req = JSON.parse(chunk.toString("utf8"));
    } catch (e) {
        console.error("Malformed request:", e);
        return;
    }
    
    const { url, headers } = req;
    const parsed = new URL(url);
    const filePath = parsed.pathname === "/" || parsed.pathname === "" ? "/index.html" : parsed.pathname;
    
    await lookUp(parsed.hostname)
    
    try {
        const entry = await drive.entry(filePath);
        if (!entry || !entry.value || !entry.value.blob || !entry.value.blob.byteLength) {
            IPC.write(Buffer.from("ERROR:File not found"));
            IPC.write(Buffer.from("END_OF_RESOURCE"));
            return;
        }
        
        const contentLength = entry.value.blob.byteLength;
        
        // Handle Range requests
        const rangeHeader = headers?.Range || headers?.range;
        let start = 0;
        let end = contentLength - 1;
        
        if (rangeHeader) {
            const match = rangeHeader.match(/bytes=(\d+)-(\d*)/);
            if (match) {
                start = parseInt(match[1], 10);
                if (match[2]) {
                    end = parseInt(match[2], 10);
                }
                // Clamp to content length
                if (end >= contentLength) end = contentLength - 1;
                if (start > end) start = 0; // fallback
            }
        }
        
        const mimeType = getMimeType(filePath);
        
        const responseHeaders = {
            "Content-Type": mimeType,
            "Content-Length": (end - start + 1).toString(),
            "Accept-Ranges": "bytes"
        };
        
        if (rangeHeader) {
            responseHeaders["Content-Range"] = `bytes ${start}-${end}/${contentLength}`;
        }
        
        const responseMeta = {
            statusCode: rangeHeader ? 206 : 200,
            headers: responseHeaders
        };
        
        console.log(responseMeta)
        
        IPC.write(Buffer.from(JSON.stringify(responseMeta)));
        
        const rs = drive.createReadStream(filePath, { start, end });
        
        rs.on("data", (data) => {
            console.log("📤 Sending chunk of size", data.length);
            IPC.write(data);
        });
        
        rs.on("error", (err) => {
            IPC.write(Buffer.from(`ERROR:${err.message}`));
            IPC.write(Buffer.from("END_OF_RESOURCE"));
        });
        
        rs.on("end", () => {
            IPC.write(Buffer.from("END_OF_RESOURCE"));
        });
        
    } catch (err) {
        console.error("Unhandled error:", err);
        IPC.write(Buffer.from(`ERROR:${err.message}`));
        IPC.write(Buffer.from("END_OF_RESOURCE"));
    }
});

function getMimeType(filePath) {
    if (filePath.endsWith('.html')) return 'text/html';
    if (filePath.endsWith('.css')) return 'text/css';
    if (filePath.endsWith('.js')) return 'application/javascript';
    if (filePath.endsWith('.mov')) return 'video/quicktime';
    if (filePath.endsWith('.mp4')) return 'video/mp4';
    if (filePath.endsWith('.png')) return 'image/png';
    
    return 'application/octet-stream';
}

async function lookUp(driveKey) {
    
    let found = false;
    for await (const dkey of store.list()) {
        console.log(dkey.toString('hex'))
        if (dkey.toString('hex') === driveKey) {
            found = true;
            break;
        }
    }
    
    if (!found) {
        drive = new Hyperdrive(store, driveKey);
        await drive.ready();
        
        console.log("🔍 Drive not found in store, joining swarm...");
        swarm.join(drive.discoveryKey);
        swarm.on("connection", (conn) => {
            console.log("🔗 Peer connected via Hyperswarm");
            store.replicate(conn);
        });
        await swarm.flush();
    } else {
        console.log("✅ Drive found in store. Skipping swarm join.");
    }
}

