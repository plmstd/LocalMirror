import { GITHUB_URL } from "@/consts";

export const whatItIscontent = `## 🧭 What It Is

YeOldBackup is a simple app for **manually backing up folders or hard drives on macOS**.  
It uses the trusted \`rsync\` tool under the hood — but with a clean graphical interface.

You choose a **source** folder or hard drive (where your files are) and a **target** folder or hard drive (where you want the backup), and YeOldBackup will **mirror** the source to the target.  
That means: new files are copied, changed files are updated, and files in the target that don’t exist in the source are deleted.

It's like a super-visible Time Machine. No cloud. No background syncing. Just you and your files.`;

export const whyYouMightLikeItContent = `## ✨ Why You Might Like It

- No Terminal, no \`rsync\` flags to remember
- No subscription, no bloat, no cloud dependencies
- Open source and free
- Built with love (and AI) for local-first tools
- Perfect for:
  - External drive backups
  - Manual file mirroring`;

export const howItWorksContent = `## 🛠️ How It Works

1. You select a **source** and **target** folder.
2. The app runs a **dry run** using \`rsync\` to show what would be copied, changed, or deleted.
3. If a large number of deletions are detected, you’ll be asked to confirm.
4. You’ll see a **progress bar** and the file currently being transferred.
5. When it’s done, a full **report** appears with all the \`rsync\` details.
6. The app remembers your backups for future reuse.

> Important: The **target folder becomes an exact copy** of the source. Anything in the target that doesn’t exist in the source will be deleted.`;

export const useWithCautionContent = `## ⚠️ Use With Caution

YeOldBackup is a tool, not a safety net. It’s provided “as is”: vibe-coded and minimal. Please read carefully:

- **Deletions are permanent**. The target folder is mirrored.
- **Double-check** source and target paths before syncing.
- **Full Disk Access is required** on macOS, especially for external or system folders.
- **External drives** must be connected and accessible before launching the app.
- **You should have other backups** in case something goes wrong.

Use at your own risk. Always be careful with your data.`;

export const gettingStartedContent = `## 🧩 Getting Started

1. **[Download the App](/api/download)**
2. Move \`YeOldBackup.app\` to your Applications folder
3. Launch the app
4. Grant Full Disk Access:
   - Open **System Settings → Privacy & Security → Full Disk Access**
   - Add \`YeOldBackup.app\` and enable it
5. Select your source and target folders
6. Click **"Sync Now"** when ready

> You can also clone the repo and build it yourself in Xcode if you're into that.`;

export const faqContent = `## ❓ FAQ

**Does this replace Time Machine?**  
No. Time Machine does automatic backups over time. YeOldBackup is manual and minimal.

**Can I use it with external drives?**  
Yes. Just make sure the drive is mounted.

**Does it support network drives?**  
It can work, but performance depends on the network. Use with caution.

**What does “mirror” mean exactly?**  
It means the target becomes a copy of the source. Files not in the source get deleted from the target.

**Does it run in the background?**  
Nope. It only does what you tell it to do. No hidden services.`;

export const aboutContent = `## 👨‍🔧 About This Project

YeOldBackup was vibe coded as a side project. It’s intentionally minimal, open source, and not meant to be a commercial product.

If you find it useful, that’s great. If not, that’s fine too. Either way: back up your stuff ✌️`;

export const contributingContent = `## 🤝 Contributing

This project is small and vibe-coded, but all improvements are welcome!

If you notice something that could be better, cleaner, safer, or more helpful, feel free to open a PR. Whether it's fixing a bug, improving UI details, or adding a feature, it's appreciated 🙌

[→ Contribute on GitHub](${GITHUB_URL})`;
