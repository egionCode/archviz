# ArchViz

Um floor planner/ArchViz 3D feito em Godot. O projeto permite desenhar uma
planta baixa com medidas reais e visualizar o resultado em planta, perspectiva
e primeira pessoa.

## Estado atual

- Mundo 3D com grade métrica e snap de 1 m.
- Ferramenta de parede com comprimento digitável, espessura configurável e
  snap angular de 45°.
- Snap em pontas, no corpo das guias de medição e em conexões de paredes.
- Geração automática de piso ao fechar um contorno simples.
- Blocos de junção para fechar conexões angulares entre paredes.
- Ferramenta de medição com comprimento digitável.
- Ferramenta de seleção, hover e exclusão por menu radial.
- Histórico de desfazer/refazer: `Ctrl+Z` e `Ctrl+Y`.
- Três visualizações: planta ortográfica, perspectiva e primeira pessoa.

## Controles principais

| Ação | Controle |
| --- | --- |
| Alternar visualização | `1`, `2`, `3` |
| Desfazer / refazer | `Ctrl+Z` / `Ctrl+Y` |
| Cancelar desenho ou medição | `Esc` |
| Zoom da planta | Roda do mouse |
| Mover a planta | Botão do meio do mouse |
| Mover em primeira pessoa | `W`, `A`, `S`, `D` |
| Olhar em primeira pessoa | Segurar botão direito do mouse |

## Fluxo de parede

1. Selecione **Parede**.
2. Clique na origem ou em uma ponta existente.
3. Mova o cursor para orientar a prévia ou informe o comprimento em metros.
4. Clique novamente, ou pressione `Enter` após digitar a medida, para criar.

## Como executar

Abra `project.godot` no Godot 4.7 ou execute:

```bash
godot --path .
```

## Contribuição

A branch `main` é protegida: mudanças devem passar por pull request e exigem
aprovação do proprietário do repositório.
