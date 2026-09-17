#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <termios.h>
#include <unistd.h>

static const char *prompt_from_args(int argc, char **argv) {
    const char *prompt = "Password: ";
    for (int i = 1; i < argc; ++i) {
        if ((strcmp(argv[i], "-p") == 0 || strcmp(argv[i], "--prompt") == 0)
            && i + 1 < argc) {
            prompt = argv[++i];
        } else if (strncmp(argv[i], "--prompt=", 9) == 0) {
            prompt = argv[i] + 9;
        }
    }
    return prompt;
}

static void write_prompt(const char *prompt, int split_prompt) {
    size_t length = strlen(prompt);
    if (split_prompt && length > 1) {
        size_t midpoint = length / 2;
        fwrite(prompt, 1, midpoint, stdout);
        fflush(stdout);
        usleep(100000);
        fwrite(prompt + midpoint, 1, length - midpoint, stdout);
    } else {
        fputs(prompt, stdout);
    }
    fflush(stdout);
}

int main(int argc, char **argv) {
    const char *prompt = prompt_from_args(argc, argv);
    const char *expected = getenv("P3_TEST_SUDO_PASSWORD");
    const char *prompts_env = getenv("P3_TEST_SUDO_PROMPTS");
    const char *exit_env = getenv("P3_TEST_SUDO_EXIT");
    int ignore_prompt = getenv("P3_TEST_SUDO_IGNORE_PROMPT") != NULL;
    int split_prompt = getenv("P3_TEST_SUDO_SPLIT_PROMPT") != NULL;
    int prompts = prompts_env ? atoi(prompts_env) : 2;
    int exit_code = exit_env ? atoi(exit_env) : 7;
    char input[256];

    if (!expected) expected = "p3-secret";
    if (ignore_prompt) prompt = "Password: ";

    for (int attempt = 0; attempt < prompts; ++attempt) {
        struct termios oldt, noecho;
        write_prompt(prompt, split_prompt);
        if (tcgetattr(STDIN_FILENO, &oldt) != 0) return 97;
        noecho = oldt;
        noecho.c_lflag &= ~(ECHO);
        if (tcsetattr(STDIN_FILENO, TCSANOW, &noecho) != 0) return 97;
        if (!fgets(input, sizeof input, stdin)) {
            tcsetattr(STDIN_FILENO, TCSANOW, &oldt);
            return 96;
        }
        tcsetattr(STDIN_FILENO, TCSANOW, &oldt);
        input[strcspn(input, "\r\n")] = '\0';
        fputc('\n', stdout);
        fflush(stdout);
        if (strcmp(input, expected) != 0) {
            printf("__P3_SUDO_BAD__%d\n", attempt + 1);
            fflush(stdout);
            return 98;
        }
    }

    printf("__P3_SUDO_OK__%d\n", prompts);
    fflush(stdout);
    return exit_code;
}
