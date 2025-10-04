
const { IPC } = BareKit
const Hyperswarm = require('hyperswarm');
const Hypercore = require('hypercore');
const b4a = require('b4a');
const Corestore = require('corestore');
const Hyperdrive = require('hyperdrive');

//IPC.setEncoding('utf8');

// create a Corestore instance
const store = new Corestore("/tmp/landmark");
const swarm = new Hyperswarm();

const key = b4a.from("9e00d79f06b6cea4b2708acbdaecfffa4014b3fca3891bed3446964a36e6b649", "hex");
let drive;

IPC.on("data", async (chunk) => {
    const requestURLString = chunk.toString('utf8');
    try {
        const url = new URL(requestURLString);
        // 2. Extract the path. Use '/index.html' if the path is just '/'
        const filePath = url.pathname === '/' || url.pathname === '' ? '/index.html' : url.pathname;
        
        console.log(`Requested file path: ${filePath}`);
        
        // 3. Determine the correct MIME type (CRUCIAL for video playback)
        const mimeType = getMimeType(filePath);
        
        // 4. Send the mime type back to Swift (protocol requirement for the scheme handler)
        IPC.write(Buffer.from(`MIMETYPE:${mimeType}`, 'utf8'));
        
//        let contentLength = null;
//        for await (const file of drive.list('/')) {
//            if (file.key === filePath) {
//                if (file.value?.blob?.byteLength) {
//                    contentLength = file.value.blob.byteLength;
//                    IPC.write(`CONTENTLENGTH:${contentLength}`);
//                }
//                break;
//            }
//        }
        
        // 5. Create the stream for the requested file
        const rs = drive.createReadStream(filePath);
        
        rs.on('data', (data) => {
            IPC.write(data);
        });
        
        rs.on('error', (err) => {
            console.error(`Stream error for ${filePath}:`, err);
            // Send an error marker and EOF
            IPC.write(Buffer.from(`ERROR:${err.message}`, 'utf8'));
            IPC.write(Buffer.from("END_OF_RESOURCE", 'utf8'));
        });
        
        rs.on('end', () => {
            console.log(`Finished streaming ${filePath}`);
            // 6. Send EOF marker to close the stream on the Swift side
            IPC.write(Buffer.from("END_OF_RESOURCE", 'utf8'));
        });
        
    } catch (error) {
        console.error('Error processing IPC data or URL:', error);
        IPC.write(b4a.from(`ERROR:${error.message}`));
        IPC.write(b4a.from("END_OF_RESOURCE"));
    }
    
});

function getMimeType(filePath) {
    if (filePath.endsWith('.html')) return 'text/html';
    if (filePath.endsWith('.css')) return 'text/css';
    if (filePath.endsWith('.js')) return 'application/javascript';
    if (filePath.endsWith('.mov')) return 'video/quicktime';
    if (filePath.endsWith('.mp4')) return 'video/mp4';
    return 'application/octet-stream';
}

async function serveFile() {
    drive = new Hyperdrive(store, key);
    await drive.ready();
    
    swarm.on("connection", (conn) => {
        console.log("reaching out in p2p")
        store.replicate(conn)
    });
    swarm.join(drive.discoveryKey);
    await swarm.flush();
}

serveFile()
