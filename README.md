[![Made in Ukraine](https://img.shields.io/badge/made_in-ukraine-ffd700.svg?labelColor=0057b7)](https://stand-with-ukraine.pp.ua)
[![Stand With Ukraine](https://raw.githubusercontent.com/vshymanskyy/StandWithUkraine/main/badges/StandWithUkraine.svg)](https://stand-with-ukraine.pp.ua)

# EdgeBus'es Ephemeral CI/CD Runner

Work In Progress ...

#StandWithUkraine 💙💛
----

#RussiaInvadedUkraine on 24 of February 2022, at 5.00 AM the armed forces of the Russian Federation  attacked Ukraine. Please, Stand with Ukraine, stay tuned for updates on Ukraine’s official sources and channels in English and support Ukraine in its fight for freedom and democracy in Europe.

- 💵 [**Sternenko Community**](https://www.sternenkofund.org/en) — foundation is established to continuously provide Ukrainian Defense Forces with drones, primarily of the FPV type, as well as to promote the development of unmanned technologies.
- 💵 [**Come Back Alive**](https://savelife.in.ua/en/donate-en/) — funds used to buy equipment for frontline soldiers as well as territorial defense units.
- 💵 [**Ukrainian Red Cross**](https://redcross.org.ua/en/donate/) — provides humanitarian relief to Ukrainians affected by the war.

[![Stand With Ukraine](https://raw.githubusercontent.com/vshymanskyy/StandWithUkraine/main/banner2-direct.svg)](https://stand-with-ukraine.pp.ua)


## Overview (en)

TBD

## Overview (uk)

Маємо:

1. QEMU віртуальна машина (VM Runner) з:
    * Сінхронізація годинника на старті системи
    * `git`, `git-lfs` та інший софт для білдів
    * GitLab Runner в режимі `shell`
1. `/etc/local.d/qemu-vm-launcher.start`
    * скріпт на хості (гіпервізорі)
    * скріпт запускаєтся з запуском системи
    * скпіпт в нескінченному цилкі робить наступне:
        запускає віртуальну машину (VM Runner) з параметром `-snapshot`

Як це працює:

0. Після завантаження гіпервізора, стартує скріпт `/etc/local.d/qemu-vm-launcher.start`
0. Скріпт запускає віртуальну машину (VM Runner) та чекає поки вона не завершиться (вимкнеться)
0. Віртуальна машина (VM Runner) завантажується, сінкає годинник, стартує GitLab Runner сервіс, та очікує завдання від GitLab CI
0. В якийся момент в GitLab CI з'являється завдання для цього раннера. VM Runner підхватує завдання і виконує його.
0. Після виконання завдання, віртуальна машина (VM Runner) програмно виключається завдяки конфигурації GitLab Runner `cleanup_exec = "poweroff"`
0. З завершенням роботи віртуальної машини (VM Runner) зникають всі модифікації так як вона була стартована з параметром `-snapshot`
0. Скріпт завершує ітерацію і знов переходить до запуску віртуальної машини (VM Runner)

🔥🔥🔥 Цей флоу ніколи не змінуює стан віртуальної машини (VM Runner). Кожен новий запуск як з чистого аркушу. 🔥🔥🔥

## References

- [Close to perfect Gitlab CI runner setup on VMs with KVM/qemu](https://aljax.us/how-to-setup-gitlab-runners-in-kvm-qemu-virtual-machines/)
