/* initrd/mkinitrd.c — Ramdisk image builder
 *
 * Packs files into the ramdisk format that vfs.fd expects.
 *
 * Format:
 *   u32 num_entries
 *   For each entry:
 *     u32 name_len
 *     char[name_len] name (no null terminator)
 *     u32 type (1=file, 2=dir)
 *     u64 size
 *     u64 data_offset (from start of ramdisk)
 *   File data follows
 *
 * Usage:
 *   gcc -o mkinitrd initrd/mkinitrd.c
 *   ./mkinitrd initrd/files/ output/initrd.img
 *
 * Then add to GRUB config:
 *   module2 /boot/initrd.img
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <dirent.h>
#include <sys/stat.h>

#define MAX_FILES 256
#define MAX_NAME_LEN 256

typedef struct {
    char name[MAX_NAME_LEN];
    uint32_t type;
    uint64_t size;
    uint8_t *data;
} Entry;

int main(int argc, char **argv) {
    if (argc < 3) {
        fprintf(stderr, "Usage: %s <input_dir> <output_file>\n", argv[0]);
        return 1;
    }

    const char *input_dir = argv[1];
    const char *output_file = argv[2];

    DIR *dir = opendir(input_dir);
    if (!dir) {
        perror("opendir");
        return 1;
    }

    Entry entries[MAX_FILES];
    int num_entries = 0;

    /* Read all files from input directory */
    struct dirent *de;
    while ((de = readdir(dir)) != NULL && num_entries < MAX_FILES) {
        if (de->d_name[0] == '.') continue;  /* skip hidden */

        char path[512];
        snprintf(path, sizeof(path), "%s/%s", input_dir, de->d_name);

        struct stat st;
        if (stat(path, &st) != 0) continue;

        if (S_ISREG(st.st_mode)) {
            strncpy(entries[num_entries].name, de->d_name, MAX_NAME_LEN - 1);
            entries[num_entries].name[MAX_NAME_LEN - 1] = '\0';
            entries[num_entries].type = 1;  /* file */
            entries[num_entries].size = st.st_size;

            FILE *f = fopen(path, "rb");
            if (!f) {
                fprintf(stderr, "Cannot open %s\n", path);
                continue;
            }
            entries[num_entries].data = malloc(st.st_size);
            fread(entries[num_entries].data, 1, st.st_size, f);
            fclose(f);

            printf("[mkinitrd] %s (%lu bytes)\n",
                   entries[num_entries].name, entries[num_entries].size);
            num_entries++;
        }
    }
    closedir(dir);

    /* Calculate header size */
    uint32_t header_size = 4;  /* num_entries */
    for (int i = 0; i < num_entries; i++) {
        header_size += 4 + strlen(entries[i].name);  /* name_len + name */
        header_size += 4;  /* type */
        header_size += 8;  /* size */
        header_size += 8;  /* data_offset */
    }

    /* Calculate data offsets */
    uint64_t data_offset = header_size;
    for (int i = 0; i < num_entries; i++) {
        data_offset += entries[i].size;
    }

    /* Write output */
    FILE *out = fopen(output_file, "wb");
    if (!out) {
        perror("fopen output");
        return 1;
    }

    /* Write num_entries */
    uint32_t n = num_entries;
    fwrite(&n, 4, 1, out);

    /* Write each entry header */
    uint64_t current_offset = header_size;
    for (int i = 0; i < num_entries; i++) {
        uint32_t name_len = strlen(entries[i].name);
        fwrite(&name_len, 4, 1, out);
        fwrite(entries[i].name, 1, name_len, out);
        fwrite(&entries[i].type, 4, 1, out);
        fwrite(&entries[i].size, 8, 1, out);
        fwrite(&current_offset, 8, 1, out);
        current_offset += entries[i].size;
    }

    /* Write file data */
    for (int i = 0; i < num_entries; i++) {
        fwrite(entries[i].data, 1, entries[i].size, out);
        free(entries[i].data);
    }

    fclose(out);

    printf("[mkinitrd] Wrote %d entries, %u header bytes, %lu total bytes\n",
           num_entries, header_size, current_offset);
    printf("[mkinitrd] Output: %s\n", output_file);

    return 0;
}
